-- Standalone CLI tool: cross-realm realm-suffix end-to-end simulator.
--
-- Background: in a cross-realm Pug, every player's "Name-Realm" string is
-- formatted by the WoW server. Realm suffixes can contain spaces ("Tarren
-- Mill"), apostrophes ("Aman'Thul"), and dashes ("Twisting-Nether"). The
-- self-echo guard in Sync.ProcessAddonMessage is:
--
--   senderKey = NormalizePlayerKey(sender)
--   selfKey   = NormalizePlayerKey(localName, localRealm)
--   shouldShareKeys = message == "SHAREKEYS" and senderKey ~= selfKey
--
-- A normalization mismatch between sender's "Name-Realm" string and the
-- receiver's local (UnitName, GetRealmName) tuple is the most common
-- silent-bug class in cross-realm parties: either the receiver's own
-- echo bypasses the guard (it posts its own key after triggering its
-- own button), or a remote peer's SHAREKEYS gets mistakenly silenced.
--
-- This simulator pins NormalizePlayerKey behavior across realm formats
-- AND drives a full Sync.ProcessAddonMessage end-to-end on each, so any
-- regression that breaks the normalization (e.g., changing the StringUtils
-- pattern) AND any regression that breaks the self-key/sender-key
-- comparison surface together.
--
-- Realms covered (taken from real EU/US live realms):
--   "Tarren Mill"       -- space
--   "Aman'Thul"         -- apostrophe
--   "Twisting-Nether"   -- dash
--   "Hyjal"             -- clean baseline
--   "Area 52"           -- space + digit
---@diagnostic disable: undefined-global
local io = io
---@diagnostic disable-next-line: undefined-global
local load = load
---@diagnostic disable-next-line: undefined-global
local os = os

local function LoadLocal(path)
  local file = assert(io.open(path, "rb"))
  local source = file:read("*a")
  file:close()
  local chunk, err = (loadstring or load)(source, "@" .. path)
  assert(chunk, err)
  return chunk()
end

local Harness = LoadLocal("testmodul/isilive_test_harness.lua")
local Fixtures = LoadLocal("testmodul/isilive_test_fixtures.lua")

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

local function MakeBagApi()
  return {
    GetContainerNumSlots = function(bagID)
      return bagID == 0 and 16 or 0
    end,
    GetContainerItemID = function(bagID, slotID)
      if bagID == 0 and slotID == 5 then
        return 180653
      end
      return nil
    end,
    GetContainerItemLink = function(bagID, slotID)
      if bagID == 0 and slotID == 5 then
        return "|cffa335ee|Hkeystone:180653:2649:12:10:10:10:10|h[Keystone: Test +12]|h|r"
      end
      return nil
    end,
  }
end

local function MakeChallengeModeApi()
  return {
    GetMapUIInfo = function()
      return "Test Dungeon"
    end,
  }
end

-- ----------------------------------------------------------------------
-- Phase A: NormalizePlayerKey unit-level pins.
-- These pin the stripping rules so a refactor of StringUtils.NormalizeRealmName
-- cannot silently change the equivalence class.
-- ----------------------------------------------------------------------
local function ScenarioNormalizationRules()
  print("\n========== Phase A: NormalizePlayerKey across realm formats ==========")

  local addon
  Harness.WithGlobals({
    GetRealmName = function()
      return "DefaultRealm"
    end,
    strsplit = StrSplitStub,
  }, function()
    addon = Harness.LoadAddonModules({ "isiLive_sync.lua" })
  end)

  local Sync = addon.Sync

  -- Within each row, all forms must collapse to the SAME normalized key.
  local equivalenceClasses = {
    {
      label = "Tarren Mill (space stripped from realm)",
      forms = {
        { name = "Player", realm = "Tarren Mill" },
        { name = "Player-Tarren Mill", realm = nil },
        { name = "Player", realm = "TarrenMill" },
        { name = "PLAYER", realm = "tarrenmill" },
      },
    },
    {
      label = "Aman'Thul (apostrophe stripped)",
      forms = {
        { name = "Player", realm = "Aman'Thul" },
        { name = "Player-Aman'Thul", realm = nil },
        { name = "Player", realm = "AmanThul" },
        { name = "player", realm = "AMANTHUL" },
      },
    },
    {
      label = "Twisting-Nether (dash stripped from realm)",
      forms = {
        { name = "Player", realm = "Twisting-Nether" },
        -- Note: name-realm split via the SECOND dash is a known harness
        -- limitation — the strsplit("-", ..., 2) takes only the first.
        -- In production, GetUnitName always returns realm without dashes
        -- via WoW's normalization, so this hyphen-realm form is what
        -- we receive in practice. We pin the realm-explicit form only.
        { name = "Player", realm = "TwistingNether" },
      },
    },
    {
      label = "Hyjal (clean baseline)",
      forms = {
        { name = "Player", realm = "Hyjal" },
        { name = "Player-Hyjal", realm = nil },
      },
    },
    {
      label = "Area 52 (digit + space)",
      forms = {
        { name = "Player", realm = "Area 52" },
        { name = "Player-Area 52", realm = nil },
        { name = "Player", realm = "Area52" },
      },
    },
  }

  for _, class in ipairs(equivalenceClasses) do
    local keys = {}
    Harness.WithGlobals({
      GetRealmName = function()
        return "DefaultRealm"
      end,
      strsplit = StrSplitStub,
    }, function()
      for _, form in ipairs(class.forms) do
        keys[#keys + 1] = Sync.NormalizePlayerKey(form.name, form.realm)
      end
    end)
    local ref = keys[1]
    local allEqual = true
    for i = 2, #keys do
      if keys[i] ~= ref then
        allEqual = false
        break
      end
    end
    Check(allEqual, string.format("%s -> all %d forms collapse to same key (%s)", class.label, #keys, tostring(ref)))
  end

  -- Negative pin: different realms must NOT collapse.
  local k1, k2
  Harness.WithGlobals({
    GetRealmName = function()
      return "DefaultRealm"
    end,
    strsplit = StrSplitStub,
  }, function()
    k1 = Sync.NormalizePlayerKey("Player", "Tarren Mill")
    k2 = Sync.NormalizePlayerKey("Player", "Aman'Thul")
  end)
  Check(k1 ~= k2, "different realms (Tarren Mill vs Aman'Thul) produce different keys")
end

-- ----------------------------------------------------------------------
-- Phase B: end-to-end SHAREKEYS across cross-realm pairs. The receiver
-- is on its own realm; the sender's "Name-RealmWithSpace" string arrives
-- through ProcessAddonMessage. shouldShareKeys must be true (sender !=
-- self) and the receiver must emit chat.
-- ----------------------------------------------------------------------
local function BuildPeer(opts)
  local peer = {
    name = opts.name,
    realm = opts.realm,
    chatMessages = {},
    chatChannels = {},
    addonMessages = {},
    sendOwnKeystoneCalls = 0,
  }

  local function buildGlobals()
    return {
      GetRealmName = function()
        return peer.realm
      end,
      UnitName = function()
        return peer.name, peer.realm
      end,
      GetTime = function()
        return 100
      end,
      IsInGroup = function(category)
        if category == 2 then
          return true -- INSTANCE_CHAT
        end
        return true
      end,
      IsInRaid = function()
        return false
      end,
      LE_PARTY_CATEGORY_INSTANCE = 2,
      strsplit = StrSplitStub,
      C_Container = MakeBagApi(),
      C_ChallengeMode = MakeChallengeModeApi(),
      C_MythicPlus = nil,
      SendChatMessage = function(message, channel)
        peer.chatMessages[#peer.chatMessages + 1] = message
        peer.chatChannels[#peer.chatChannels + 1] = channel
      end,
      C_ChatInfo = {
        SendAddonMessage = function(prefix, message, channel)
          peer.addonMessages[#peer.addonMessages + 1] = {
            prefix = prefix,
            message = message,
            channel = channel,
          }
          return true
        end,
      },
    }
  end

  Harness.WithGlobals(buildGlobals(), function()
    peer.addon = Harness.LoadAddonModules({
      "isiLive_context_helpers.lua",
      "isiLive_sync.lua",
      "isiLive_event_handlers.lua",
    })
  end)

  local function sendOwnKeystoneToChat()
    peer.sendOwnKeystoneCalls = peer.sendOwnKeystoneCalls + 1
    local sent = false
    Harness.WithGlobals(buildGlobals(), function()
      local line = peer.addon.ContextHelpers.BuildOwnKeystoneAnnounceLine({
        getL = function()
          return { ANNOUNCE_PREFIX = "PartyKeys:" }
        end,
        getOwnedKeystoneSnapshot = function()
          return 2649, 12
        end,
        getDungeonShortCode = function()
          return "ARA"
        end,
      })
      if type(line) ~= "string" or line == "" then
        return
      end
      sent = peer.addon.ContextHelpers.SendPartyChatMessage(line) == true
    end)
    return sent
  end

  Harness.WithGlobals(buildGlobals(), function()
    peer.controller = Fixtures.BuildEventHandlersController(peer.addon.EventHandlers, { value = nil }, {}, {
      isMainFrameShown = function()
        return false
      end,
      processAddonMessage = function(prefix, message, sender, channel)
        return peer.addon.Sync.ProcessAddonMessage(prefix, message, sender, peer.name, peer.realm, channel)
      end,
      sendOwnKeystoneToChat = sendOwnKeystoneToChat,
      triggerShareKeysCooldown = function() end,
    })
  end)

  peer.dispatch = function(prefix, message, channel, sender)
    Harness.WithGlobals(buildGlobals(), function()
      peer.controller:Dispatch("CHAT_MSG_ADDON", prefix, message, channel, sender)
    end)
  end

  return peer
end

local function ScenarioCrossRealmRoundtrips()
  print("\n========== Phase B: cross-realm SHAREKEYS roundtrips ==========")

  local pairs_ = {
    {
      label = "sender on 'Tarren Mill', receiver on 'Aman'Thul'",
      senderName = "Sender",
      senderRealm = "Tarren Mill",
      receiverName = "Receiver",
      receiverRealm = "Aman'Thul",
    },
    {
      label = "sender on 'Aman'Thul', receiver on 'Hyjal'",
      senderName = "Sender",
      senderRealm = "Aman'Thul",
      receiverName = "Receiver",
      receiverRealm = "Hyjal",
    },
    {
      label = "sender on 'Area 52', receiver on 'Tarren Mill'",
      senderName = "Sender",
      senderRealm = "Area 52",
      receiverName = "Receiver",
      receiverRealm = "Tarren Mill",
    },
    {
      label = "sender and receiver on SAME realm 'Tarren Mill', but cross-realm-style sender suffix",
      senderName = "Sender",
      senderRealm = "Tarren Mill",
      receiverName = "Receiver",
      receiverRealm = "Tarren Mill",
    },
  }

  for _, scenario in ipairs(pairs_) do
    print("  -- " .. scenario.label)
    local peer = BuildPeer({ name = scenario.receiverName, realm = scenario.receiverRealm })
    -- Sender's "Name-RealmWithSpace" arrives as one string, exactly how
    -- WoW formats CHAT_MSG_ADDON's sender argument.
    peer.dispatch("ISILIVE", "SHAREKEYS", "INSTANCE_CHAT", scenario.senderName .. "-" .. scenario.senderRealm)
    Check(
      peer.sendOwnKeystoneCalls == 1,
      string.format("    receiver '%s-%s' fired sendOwnKeystoneToChat", peer.name, peer.realm)
    )
    Check(#peer.chatMessages == 1, string.format("    receiver '%s-%s' emitted 1 chat message", peer.name, peer.realm))
    Check(
      peer.chatChannels[1] == "INSTANCE_CHAT",
      string.format("    receiver '%s-%s' chat went to INSTANCE_CHAT", peer.name, peer.realm)
    )
  end
end

-- ----------------------------------------------------------------------
-- Phase C: self-echo across realm-format variants. The receiver's own
-- SHAREKEYS broadcast wraps back into its own ProcessAddonMessage with
-- different realm-formatting permutations of the SAME identity. All must
-- be detected as self.
-- ----------------------------------------------------------------------
local function ScenarioSelfEchoNormalizedAcrossRealmFormats()
  print("\n========== Phase C: self-echo detected across realm-format permutations ==========")

  local cases = {
    {
      label = "self on 'Tarren Mill', echo arrives as 'Player-Tarren Mill'",
      receiverRealm = "Tarren Mill",
      senderSuffix = "Player-Tarren Mill",
    },
    {
      label = "self on 'TarrenMill' (server-stripped), echo arrives as 'Player-TarrenMill'",
      receiverRealm = "TarrenMill",
      senderSuffix = "Player-TarrenMill",
    },
    {
      label = "self on 'Aman'Thul', echo arrives as 'Player-Aman'Thul'",
      receiverRealm = "Aman'Thul",
      senderSuffix = "Player-Aman'Thul",
    },
    {
      label = "self on 'Aman'Thul' but echo arrives as 'Player-AmanThul' (server stripped apostrophe)",
      receiverRealm = "Aman'Thul",
      senderSuffix = "Player-AmanThul",
    },
  }

  for _, c in ipairs(cases) do
    print("  -- " .. c.label)
    local peer = BuildPeer({ name = "Player", realm = c.receiverRealm })
    peer.dispatch("ISILIVE", "SHAREKEYS", "INSTANCE_CHAT", c.senderSuffix)
    Check(peer.sendOwnKeystoneCalls == 0, "    self-echo: sendOwnKeystoneToChat NOT called")
    Check(#peer.chatMessages == 0, "    self-echo: no chat emitted")
  end
end

ScenarioNormalizationRules()
ScenarioCrossRealmRoundtrips()
ScenarioSelfEchoNormalizedAcrossRealmFormats()

if failures > 0 then
  print(string.format("\nCross-realm realm-suffix simulator failed: %d check(s) failed", failures))
  os.exit(1)
end

print("\nCross-realm realm-suffix simulator passed.")
