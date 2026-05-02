-- Standalone CLI tool: simulates a hidden main frame in a party group going
-- through a /reload, and verifies that the addon-message ingest still answers
-- KEY / STATS / DPS / LOC / TARGET / KICK / HELLO / REQSYNC payloads after
-- the reload. The chain is UI-independent, but a regression that wires sync
-- ingest behind a "main frame visible" guard would silently break party
-- coordination — this simulator catches that.
---@diagnostic disable: undefined-global
local io = io
---@diagnostic disable-next-line: undefined-global
local load = load

local function LoadLocal(path)
  local file = assert(io.open(path, "rb"))
  local source = file:read("*a")
  file:close()
  local chunk, err = (loadstring or load)(source, "@" .. path)
  assert(chunk, err)
  return chunk()
end

local Harness = LoadLocal("testmodul/isilive_test_harness.lua")

local failures = 0

local function Check(condition, message)
  if condition then
    print("  [CHECK PASS] " .. message)
    return
  end
  failures = failures + 1
  print("  [CHECK FAIL] " .. message)
end

-- WoW's strsplit is not present in standalone Lua. The sync module calls it
-- when SplitPayload runs, so we provide a faithful enough stub that returns
-- two halves around the first separator (matching the real Blizzard signature
-- when called with max=2).
local function StrSplitStub(sep, str, max)
  local pos = str:find(sep, 1, true)
  if not pos then
    return str
  end
  if max and max >= 2 then
    return str:sub(1, pos - 1), str:sub(pos + 1)
  end
  return str:sub(1, pos - 1)
end

local function BuildSyncSession(opts)
  opts = opts or {}
  local registeredPrefixes = {}
  local sentMessages = {}

  local sync
  Harness.WithGlobals({
    strsplit = StrSplitStub,
    GetRealmName = function()
      return "Realm"
    end,
    UnitName = function()
      return "MyPlayer", "Realm"
    end,
    IsInGroup = function()
      return opts.inGroup ~= false
    end,
    IsInRaid = function()
      return false
    end,
    GetTime = function()
      return 1000
    end,
    C_ChatInfo = {
      RegisterAddonMessagePrefix = function(prefix)
        registeredPrefixes[#registeredPrefixes + 1] = prefix
        return true
      end,
      SendAddonMessage = function(prefix, payload, channel)
        sentMessages[#sentMessages + 1] = { prefix = prefix, payload = payload, channel = channel }
        return true
      end,
    },
    -- Hidden main frame: a global stand-in for "the main UI is not currently
    -- visible". Sync ingest must NOT depend on this; if a regression added a
    -- guard like `if not mainFrame:IsVisible() then return end`, this stub
    -- ensures the simulated frame reports false.
    IsiLiveMainFrame = {
      IsShown = function()
        return false
      end,
      IsVisible = function()
        return false
      end,
    },
    IsiLiveDB = {
      mainFrameWasHidden = true,
      syncEnabled = true,
    },
  }, function()
    local addon = Harness.LoadAddonModules({ "isiLive_sync.lua" })
    sync = addon.Sync
    -- Re-registering the prefix is what ApplyDBSettings does after ADDON_LOADED.
    -- The simulator records the call so we can assert it happens on every fresh
    -- session, not just the first one.
    sync.RegisterPrefix()
  end)

  return {
    sync = sync,
    registeredPrefixes = registeredPrefixes,
    sentMessages = sentMessages,
    process = function(payload, sender)
      local result
      Harness.WithGlobals({
        strsplit = StrSplitStub,
        GetRealmName = function()
          return "Realm"
        end,
        GetTime = function()
          return 1000
        end,
      }, function()
        result = sync.ProcessAddonMessage("ISILIVE", payload, sender, "MyPlayer", "Realm")
      end)
      return result
    end,
  }
end

local function CheckAllBuckets(label, session)
  print("---- " .. label)
  print(string.format("  prefixRegistrations = %d", #session.registeredPrefixes))

  Check(#session.registeredPrefixes >= 1, "prefix registration runs at least once on session start")
  Check(session.registeredPrefixes[1] == "ISILIVE", "first registered prefix is ISILIVE")

  local helloResult = session.process("HELLO:0.9.250:2:1000:hello", "Peer-OtherRealm")
  Check(helloResult ~= nil, "HELLO returns a result table")
  Check(helloResult and helloResult.shouldAck == true, "HELLO from peer requires ack — UI visibility is irrelevant")

  local reqResult = session.process("REQSYNC", "Peer-OtherRealm")
  Check(reqResult ~= nil, "REQSYNC returns a result table")
  Check(
    reqResult and reqResult.shouldRequestRefresh == true,
    "REQSYNC from peer requests a refresh response — survives /reload"
  )

  local keyResult = session.process("KEY:2649:15:1000:hello", "Peer-OtherRealm")
  Check(keyResult and keyResult.keyUpdated == true, "KEY payload is applied after /reload")
  local keyInfo = session.sync.GetPlayerKeyInfo("Peer", "OtherRealm")
  Check(
    keyInfo ~= nil and keyInfo.mapID == 2649 and keyInfo.level == 15,
    "KEY persisted into Sync state (mapID=2649, level=15)"
  )

  local statsResult = session.process("STATS:72:615:3210:1000:hello", "Peer-OtherRealm")
  Check(statsResult and statsResult.statsUpdated == true, "STATS payload is applied after /reload")
  local statsInfo = session.sync.GetPlayerStatsInfo("Peer", "OtherRealm")
  Check(
    statsInfo ~= nil and statsInfo.specID == 72 and statsInfo.ilvl == 615 and statsInfo.rio == 3210,
    "STATS persisted into Sync state (spec=72, ilvl=615, rio=3210)"
  )

  local dpsResult = session.process("DPS:250000:1000:hello", "Peer-OtherRealm")
  Check(dpsResult and dpsResult.dpsUpdated == true, "DPS payload is applied after /reload")
  local dpsInfo = session.sync.GetPlayerDpsInfo("Peer", "OtherRealm")
  Check(dpsInfo ~= nil and dpsInfo.dps == 250000, "DPS persisted into Sync state (250000)")

  local locResult = session.process("LOC:2649:1000:hello", "Peer-OtherRealm")
  Check(locResult and locResult.locUpdated == true, "LOC payload is applied after /reload")
  local locInfo = session.sync.GetPlayerLocInfo("Peer", "OtherRealm")
  Check(locInfo ~= nil and locInfo.mapID == 2649, "LOC persisted into Sync state (mapID=2649)")

  local targetResult = session.process("TARGET:2650:16:1000:hello", "Peer-OtherRealm")
  Check(targetResult and targetResult.targetUpdated == true, "TARGET payload is applied after /reload")
  local targetInfo = session.sync.GetPlayerTargetInfo("Peer", "OtherRealm")
  Check(
    targetInfo ~= nil and targetInfo.mapID == 2650 and targetInfo.level == 16,
    "TARGET persisted into Sync state (mapID=2650, level=16)"
  )

  -- KICK payload: state=1 (ready), remain=0
  local kickResult = session.process("KICK:1:0", "Peer-OtherRealm")
  Check(kickResult and kickResult.kickUpdated == true, "KICK payload is applied after /reload")
  local kickInfo = session.sync.GetPlayerKickInfo("Peer", "OtherRealm")
  Check(kickInfo ~= nil, "KICK persisted into Sync state")
  Check(kickInfo and kickInfo.hasKick == true, "KICK with state=1 records hasKick=true")
end

local function CheckStateIsolatedAfterReload(sessionOne, sessionTwo)
  -- A peer that was tracked in session 1 must NOT leak into session 2's
  -- in-memory state. Sync is file-scope state, so a fresh module load resets
  -- everything. If a future refactor migrated the storage to a global
  -- namespace, this isolation check would catch it.
  local oneInfo = sessionOne.sync.GetPlayerKeyInfo("Peer", "OtherRealm")
  Check(oneInfo ~= nil, "session 1 still has Peer key info before any session-2 process call")

  local twoSession = BuildSyncSession()
  -- session 2 immediately after fresh load — no payloads processed yet
  local twoInfoBeforeProcess = twoSession.sync.GetPlayerKeyInfo("Peer", "OtherRealm")
  Check(
    twoInfoBeforeProcess == nil,
    "session 2 fresh load has no Peer state until a payload is processed (file-scope reset)"
  )

  -- replay one payload to confirm session 2 stays operational
  local replayed = twoSession.process("KEY:2649:15:1000:hello", "Peer-OtherRealm")
  Check(replayed and replayed.keyUpdated == true, "session 2 fresh load applies first KEY payload")

  -- Suppress "unused" warning on sessionTwo: the caller passes it so a future
  -- assertion can compare session-1 vs session-2 directly.
  return sessionTwo
end

local function Run()
  print("========== Hidden-frame + group + /reload sync-ingest simulator ==========")

  print("\n---- session 1: hidden main frame, in group, fresh login ----")
  local sessionOne = BuildSyncSession({ inGroup = true })
  CheckAllBuckets("session 1 ingest", sessionOne)

  -- Simulate /reload: a fresh BuildSyncSession reloads the lua file from disk,
  -- which resets the Sync module's file-scope state. SavedVariables-equivalent
  -- DB values stay the same — represented here by re-passing the same opts.
  print("\n---- session 2: same hidden / group state, after /reload ----")
  local sessionTwo = BuildSyncSession({ inGroup = true })
  CheckAllBuckets("session 2 ingest after /reload", sessionTwo)

  print("\n---- isolation: session-2 starts clean, session-1 state does not leak ----")
  CheckStateIsolatedAfterReload(sessionOne, sessionTwo)

  if failures > 0 then
    print(string.format("\nHidden-sync reload simulator failed: %d check(s) failed", failures))
    os.exit(1)
  end

  print("\nHidden-sync reload simulator passed.")
end

Run()
