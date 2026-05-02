-- Standalone CLI tool: simulates multiple /reload cycles plus repeated Register
-- / SetEnabled storms within one session. Verifies:
--   * each fresh load isolates module state (no peer leakage across sessions)
--   * MobNameplate.SetEnabled is idempotent — multiple `true` calls do NOT
--     stack new RegisterEvent / CreateFrame allocations
--   * a SetEnabled(false) → SetEnabled(true) toggle re-registers events
--     exactly once each time
--   * Sync.RegisterPrefix tolerates being called several times per session
--     (matches what ApplyDBSettings does at file-load AND at ADDON_LOADED)
-- Memory- and hook-leak regressions in WoW addons typically only surface
-- after many /reload cycles in a single play session — this gate makes them
-- visible at preflight time instead.
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

-- Frame-mock factory shared by every simulated session. Each frame records
-- how many times it had RegisterEvent / SetScript called for which event.
local function MakeFrame()
  local f = {
    _events = {},
    _scripts = {},
    _registerEventCallsByEvent = {},
    _setScriptCallsByName = {},
  }
  function f:RegisterEvent(event)
    self._events[event] = true
    self._registerEventCallsByEvent[event] = (self._registerEventCallsByEvent[event] or 0) + 1
  end
  function f:UnregisterEvent(event)
    self._events[event] = nil
  end
  function f:UnregisterAllEvents()
    self._events = {}
  end
  function f:SetScript(name, fn)
    self._scripts[name] = fn
    self._setScriptCallsByName[name] = (self._setScriptCallsByName[name] or 0) + 1
  end
  return f
end

local function BuildSession(opts)
  opts = opts or {}
  local createdFrames = {}
  local registeredPrefixes = {}

  local globals = {
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
    CreateFrame = function()
      local frame = MakeFrame()
      createdFrames[#createdFrames + 1] = frame
      return frame
    end,
    C_NamePlate = {
      GetNamePlateForUnit = function()
        return nil
      end,
    },
    C_ScenarioInfo = {
      GetUnitCriteriaProgressValues = function()
        return nil
      end,
    },
    C_ChallengeMode = {
      IsChallengeModeActive = function()
        return false
      end,
      GetActiveChallengeMapID = function()
        return nil
      end,
    },
    C_ChatInfo = {
      RegisterAddonMessagePrefix = function(prefix)
        registeredPrefixes[#registeredPrefixes + 1] = prefix
        return true
      end,
      SendAddonMessage = function()
        return true
      end,
    },
    UnitExists = function()
      return false
    end,
    UnitReaction = function()
      return 2
    end,
    GameFontNormalOutline = {
      GetFont = function()
        return "Fonts\\FRIZQT__.TTF", 10, "OUTLINE"
      end,
    },
  }

  local addon
  Harness.WithGlobals(globals, function()
    addon = Harness.LoadAddonModules({ "isiLive_sync.lua", "isiLive_mob_nameplate.lua" })
  end)

  return {
    addon = addon,
    createdFrames = createdFrames,
    registeredPrefixes = registeredPrefixes,
    globals = globals,
    process = function(payload, sender)
      local result
      Harness.WithGlobals(globals, function()
        result = addon.Sync.ProcessAddonMessage("ISILIVE", payload, sender, "MyPlayer", "Realm")
      end)
      return result
    end,
    setNameplateEnabled = function(flag)
      Harness.WithGlobals(globals, function()
        addon.MobNameplate.SetEnabled(flag)
      end)
    end,
    registerSyncPrefix = function()
      Harness.WithGlobals(globals, function()
        addon.Sync.RegisterPrefix()
      end)
    end,
  }
end

local function CountFramesWithEvent(session, event)
  local n = 0
  for _, frame in ipairs(session.createdFrames) do
    if frame._events[event] then
      n = n + 1
    end
  end
  return n
end

local function MaxRegisterCallsForEvent(session, event)
  local maxCalls = 0
  for _, frame in ipairs(session.createdFrames) do
    local calls = frame._registerEventCallsByEvent[event] or 0
    if calls > maxCalls then
      maxCalls = calls
    end
  end
  return maxCalls
end

local function MaxSetScriptCallsFor(session, name)
  local maxCalls = 0
  for _, frame in ipairs(session.createdFrames) do
    local calls = frame._setScriptCallsByName[name] or 0
    if calls > maxCalls then
      maxCalls = calls
    end
  end
  return maxCalls
end

local function Run()
  print("========== Reload-storm simulator ==========\n")

  -- ------------------------------------------------------------------
  -- Phase 1: three sequential /reload cycles. Each cycle is a fresh Lua
  -- session — file-scope state must reset and a peer recorded in cycle N
  -- must NOT leak into cycle N+1.
  -- ------------------------------------------------------------------
  print("---- Phase 1: three /reload cycles, peer state isolated ----")
  for cycle = 1, 3 do
    local sim = BuildSession()
    local before = sim.addon.Sync.GetPlayerKeyInfo("Peer", "OtherRealm")
    Check(before == nil, string.format("cycle %d: fresh load has no Peer state before any payload", cycle))

    local result = sim.process("KEY:2649:" .. cycle .. ":1000:reload-storm", "Peer-OtherRealm")
    Check(result and result.keyUpdated == true, string.format("cycle %d: KEY payload applies on first ingest", cycle))

    local after = sim.addon.Sync.GetPlayerKeyInfo("Peer", "OtherRealm")
    Check(
      after ~= nil and after.level == cycle,
      string.format("cycle %d: KEY level=%d is the only level recorded (no leak)", cycle, cycle)
    )
  end

  -- ------------------------------------------------------------------
  -- Phase 2: within one session, fire SetEnabled(true) repeatedly. Each
  -- redundant call must short-circuit instead of stacking events / frames.
  -- ------------------------------------------------------------------
  print("\n---- Phase 2: SetEnabled(true) storm — idempotent ----")
  do
    local sim = BuildSession()
    sim.setNameplateEnabled(true)
    local frameCountAfterFirst = #sim.createdFrames
    local registerCallsForUnitAdded = MaxRegisterCallsForEvent(sim, "NAME_PLATE_UNIT_ADDED")
    Check(frameCountAfterFirst >= 1, "SetEnabled(true) creates at least one event frame on first activation")
    Check(registerCallsForUnitAdded == 1, "first SetEnabled(true) registers NAME_PLATE_UNIT_ADDED exactly once")

    for _ = 1, 4 do
      sim.setNameplateEnabled(true)
    end
    Check(
      #sim.createdFrames == frameCountAfterFirst,
      "subsequent SetEnabled(true) calls do not allocate additional event frames"
    )
    Check(
      MaxRegisterCallsForEvent(sim, "NAME_PLATE_UNIT_ADDED") == 1,
      "subsequent SetEnabled(true) calls do not re-register NAME_PLATE_UNIT_ADDED"
    )
    Check(
      MaxRegisterCallsForEvent(sim, "CHALLENGE_MODE_START") == 1,
      "subsequent SetEnabled(true) calls do not re-register CHALLENGE_MODE_START"
    )
    Check(
      MaxSetScriptCallsFor(sim, "OnEvent") == 1,
      "OnEvent script handler is set exactly once across the storm (no handler stacking)"
    )
  end

  -- ------------------------------------------------------------------
  -- Phase 3: toggle storm — true → false → true → false → true. Each
  -- "true" round must re-register events; UnregisterAllEvents wipes
  -- between rounds. We assert the invariant "after the final true round,
  -- exactly one frame is registered for NAME_PLATE_UNIT_ADDED".
  -- ------------------------------------------------------------------
  print("\n---- Phase 3: toggle storm — register / unregister cycles ----")
  do
    local sim = BuildSession()
    for round = 1, 3 do
      sim.setNameplateEnabled(true)
      Check(
        CountFramesWithEvent(sim, "NAME_PLATE_UNIT_ADDED") == 1,
        string.format("toggle round %d: exactly one frame registered for NAME_PLATE_UNIT_ADDED after enable", round)
      )
      sim.setNameplateEnabled(false)
      Check(
        CountFramesWithEvent(sim, "NAME_PLATE_UNIT_ADDED") == 0,
        string.format("toggle round %d: zero frames registered for NAME_PLATE_UNIT_ADDED after disable", round)
      )
    end
    sim.setNameplateEnabled(true)
    Check(
      CountFramesWithEvent(sim, "NAME_PLATE_UNIT_ADDED") == 1,
      "after final toggle to enabled, exactly one frame is registered (no leak)"
    )
    Check(#sim.createdFrames == 1, "toggle storm reuses the original event frame (CreateFrame called exactly once)")
  end

  -- ------------------------------------------------------------------
  -- Phase 4: Sync.RegisterPrefix is called 3× per session in real life
  -- (file-load, ADDON_LOADED, plus an explicit user toggle). The mock
  -- accepts each call but the simulator pins that none of them crash and
  -- that all calls actually fan out to C_ChatInfo (the registry is
  -- idempotent in WoW, but we still want to know if a refactor stops
  -- calling it altogether).
  -- ------------------------------------------------------------------
  print("\n---- Phase 4: RegisterPrefix can be called repeatedly ----")
  do
    local sim = BuildSession()
    local baseline = #sim.registeredPrefixes
    sim.registerSyncPrefix()
    sim.registerSyncPrefix()
    sim.registerSyncPrefix()
    Check(
      #sim.registeredPrefixes >= baseline + 3,
      "three explicit RegisterPrefix calls all fan out to C_ChatInfo.RegisterAddonMessagePrefix"
    )
    -- Every recorded prefix must equal "ISILIVE" (or one of the multi-prefix
    -- entries the module registers). Pin that no garbage prefix sneaks in.
    for _, prefix in ipairs(sim.registeredPrefixes) do
      Check(
        type(prefix) == "string" and #prefix > 0 and #prefix <= 16,
        string.format("registered prefix '%s' is a non-empty <=16-char string", tostring(prefix))
      )
    end
  end

  if failures > 0 then
    print(string.format("\nReload-storm simulator failed: %d check(s) failed", failures))
    os.exit(1)
  end

  print("\nReload-storm simulator passed.")
end

Run()
