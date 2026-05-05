-- Standalone CLI tool: SHAREKEYS multi-peer convergence simulator.
--
-- Background: today's roundtrip simulator (simulate_sender_receiver.lua)
-- pins the sender->receiver wire handoff against ONE receiver. In a real
-- 5-man party, after the leader hits "Keys teilen" all four other isiLive
-- clients must independently post their own keystone to chat. Each client
-- maintains its OWN cooldown, has its OWN bag-scan result, runs its OWN
-- ProcessAddonMessage / sendOwnKeystoneToChat closure.
--
-- This simulator stands up four full receiver controllers (each with an
-- independent ContextHelpers / Sync state slice via a per-receiver
-- BuildSession) and dispatches the same captured wire bytes into all four.
-- It pins:
--   1. Convergence: 4 distinct chat messages emitted, one per receiver.
--   2. Cooldown isolation: a per-receiver 30s self-cooldown does not bleed
--      across peers.
--   3. Self-echo guard: when the sender's own ID matches one of the four
--      receivers, that receiver alone suppresses the chat post.
--   4. Cross-realm: receivers on three different realms still produce chat
--      output (covered in detail by simulate_cross_realm_realm_suffix.lua;
--      kept here as a sanity smoke).
--
-- End-to-end discipline: each receiver's sendOwnKeystoneToChat closure
-- runs the real ContextHelpers.BuildOwnKeystoneAnnounceLine and
-- ContextHelpers.SendPartyChatMessage. The receiver Sync.ProcessAddonMessage
-- runs its real shouldShareKeys validity check.
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

local function MakeBagApi(mapID, level)
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
        return string.format(
          "|cffa335ee|Hkeystone:180653:%d:%d:10:10:10:10|h[Keystone: Test +%d]|h|r",
          mapID,
          level,
          level
        )
      end
      return nil
    end,
  }
end

local function MakeChallengeModeApi()
  return {
    GetMapUIInfo = function(mapID)
      return "Test Dungeon " .. tostring(mapID)
    end,
  }
end

-- A peer is a self-contained party member with its own realm, name,
-- keystone snapshot, capture buffers, addon module set, and EventHandlers
-- controller. We load a fresh module set per peer so per-module state
-- (lastKeystoneAt cooldowns inside ContextHelpers, message dedup tables
-- inside Sync) cannot bleed across peers.
local function BuildPeer(opts)
  local peer = {
    name = assert(opts.name, "peer.name required"),
    realm = assert(opts.realm, "peer.realm required"),
    mapID = opts.mapID or 2649,
    level = opts.level or 12,
    now = opts.now or 100,
    addonMessages = {},
    chatMessages = {},
    chatChannels = {},
    sendOwnKeystoneCalls = 0,
    cooldownAborts = 0,
    lastKeystoneAt = 0,
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
        return peer.now
      end,
      IsInGroup = function(category)
        if category == 2 then
          return opts.inInstance == true
        end
        return true
      end,
      IsInRaid = function()
        return false
      end,
      LE_PARTY_CATEGORY_INSTANCE = 2,
      strsplit = StrSplitStub,
      C_Container = MakeBagApi(peer.mapID, peer.level),
      C_ChallengeMode = MakeChallengeModeApi(),
      C_MythicPlus = nil, -- removed in Retail; force bag-scan path
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

  -- Per-peer sendOwnKeystoneToChat closure: runs real ContextHelpers under
  -- the peer's own globals scope and tracks the peer's own 30s cooldown.
  local function sendOwnKeystoneToChat()
    peer.sendOwnKeystoneCalls = peer.sendOwnKeystoneCalls + 1
    if peer.lastKeystoneAt > 0 and (peer.now - peer.lastKeystoneAt) < 30 then
      peer.cooldownAborts = peer.cooldownAborts + 1
      return false
    end
    local sent = false
    Harness.WithGlobals(buildGlobals(), function()
      local line = peer.addon.ContextHelpers.BuildOwnKeystoneAnnounceLine({
        getL = function()
          return { ANNOUNCE_PREFIX = "PartyKeys:" }
        end,
        getOwnedKeystoneSnapshot = function()
          return peer.mapID, peer.level
        end,
        getDungeonShortCode = function(mapID)
          return "MAP" .. tostring(mapID)
        end,
      })
      if type(line) ~= "string" or line == "" then
        return
      end
      sent = peer.addon.ContextHelpers.SendPartyChatMessage(line) == true
    end)
    if sent then
      peer.lastKeystoneAt = peer.now
    end
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

  peer.advanceTime = function(deltaSeconds)
    peer.now = peer.now + deltaSeconds
  end

  return peer
end

-- Build a sender that emits real Sync.SendShareKeysRequest wire bytes via
-- a captured C_ChatInfo.SendAddonMessage. Independent module load so its
-- timestamps / dedupe state do not interfere with receivers.
local function BuildSender(opts)
  local sender = {
    name = opts.name or "Leader",
    realm = opts.realm or "RealmA",
    addonMessages = {},
  }

  Harness.WithGlobals({
    GetRealmName = function()
      return sender.realm
    end,
    GetTime = function()
      return opts.now or 100
    end,
    IsInGroup = function(category)
      if category == 2 then
        return opts.inInstance == true
      end
      return true
    end,
    IsInRaid = function()
      return false
    end,
    LE_PARTY_CATEGORY_INSTANCE = 2,
    strsplit = StrSplitStub,
    C_ChatInfo = {
      SendAddonMessage = function(prefix, message, channel)
        sender.addonMessages[#sender.addonMessages + 1] = {
          prefix = prefix,
          message = message,
          channel = channel,
        }
        return true
      end,
    },
  }, function()
    local addon = Harness.LoadAddonModules({ "isiLive_sync.lua" })
    sender.ok = addon.Sync.SendShareKeysRequest()
  end)

  sender.bytes = sender.addonMessages[1]
  return sender
end

-- ----------------------------------------------------------------------
-- Scenario 1: full convergence — 1 sender + 4 receivers, all on different
-- realms (cross-realm party). All 4 receivers must emit exactly 1 chat
-- message each.
-- ----------------------------------------------------------------------
local function ScenarioConvergence4Receivers()
  print("\n========== Scenario 1: 1 sender + 4 receivers, all 4 chat ==========")

  local sender = BuildSender({ name = "Leader", realm = "RealmA", inInstance = true })
  Check(sender.ok == true, "sender SendShareKeysRequest returned true")
  Check(sender.bytes ~= nil, "sender produced wire bytes")
  Check(sender.bytes and sender.bytes.message == "SHAREKEYS", "wire message == SHAREKEYS")
  Check(sender.bytes and sender.bytes.channel == "INSTANCE_CHAT", "wire channel == INSTANCE_CHAT")

  local peers = {
    BuildPeer({ name = "Healer", realm = "RealmB", mapID = 2649, level = 12, inInstance = true }),
    BuildPeer({ name = "Tank", realm = "RealmC", mapID = 2660, level = 14, inInstance = true }),
    BuildPeer({ name = "Dps1", realm = "RealmD", mapID = 2651, level = 10, inInstance = true }),
    BuildPeer({ name = "Dps2", realm = "RealmE", mapID = 2773, level = 16, inInstance = true }),
  }

  -- Sender's wire bytes get dispatched into each receiver. Sender ID is
  -- "Leader-RealmA" -- not equal to any peer's name+realm, so all 4 must fire.
  for _, peer in ipairs(peers) do
    peer.dispatch(sender.bytes.prefix, sender.bytes.message, sender.bytes.channel, sender.name .. "-" .. sender.realm)
  end

  for i, peer in ipairs(peers) do
    Check(
      peer.sendOwnKeystoneCalls == 1,
      string.format("peer #%d (%s-%s) sendOwnKeystoneToChat called once", i, peer.name, peer.realm)
    )
    Check(#peer.chatMessages == 1, string.format("peer #%d (%s-%s) emitted 1 chat message", i, peer.name, peer.realm))
    Check(
      peer.chatChannels[1] == "INSTANCE_CHAT",
      string.format("peer #%d (%s-%s) chat went to INSTANCE_CHAT", i, peer.name, peer.realm)
    )
  end
end

-- ----------------------------------------------------------------------
-- Scenario 2: cooldown isolation. Peer1 already posted within 30s (own
-- previous SHAREKEYS). Peer2/3/4 are clean. Sender fires SHAREKEYS once.
-- Expectation: peer1 hits its own 30s cooldown and posts NOTHING; peer2/3/4
-- all post once. Pins that the cooldown is per-peer state, not bleeding
-- across BuildPeer instances.
-- ----------------------------------------------------------------------
local function ScenarioCooldownIsolation()
  print("\n========== Scenario 2: cooldown isolation across peers ==========")

  local sender = BuildSender({ name = "Leader", realm = "RealmA", inInstance = true })
  local peers = {
    BuildPeer({ name = "Healer", realm = "RealmB", inInstance = true, now = 1000 }),
    BuildPeer({ name = "Tank", realm = "RealmC", inInstance = true, now = 1000 }),
    BuildPeer({ name = "Dps1", realm = "RealmD", inInstance = true, now = 1000 }),
    BuildPeer({ name = "Dps2", realm = "RealmE", inInstance = true, now = 1000 }),
  }

  -- Mark peer1 as "just posted 5s ago".
  peers[1].lastKeystoneAt = 995

  for _, peer in ipairs(peers) do
    peer.dispatch(sender.bytes.prefix, sender.bytes.message, sender.bytes.channel, "Leader-RealmA")
  end

  Check(peers[1].cooldownAborts == 1, "peer1 cooldown aborted (last post 5s ago)")
  Check(#peers[1].chatMessages == 0, "peer1 emitted no chat (cooldown)")
  Check(#peers[2].chatMessages == 1, "peer2 emitted 1 chat (no cooldown)")
  Check(#peers[3].chatMessages == 1, "peer3 emitted 1 chat (no cooldown)")
  Check(#peers[4].chatMessages == 1, "peer4 emitted 1 chat (no cooldown)")
  Check(peers[2].cooldownAborts == 0, "peer2 had no cooldown abort")
  Check(peers[3].cooldownAborts == 0, "peer3 had no cooldown abort")
  Check(peers[4].cooldownAborts == 0, "peer4 had no cooldown abort")
end

-- ----------------------------------------------------------------------
-- Scenario 3: self-echo with one matching peer. The sender's ID equals
-- peer3's ID. peer3 must NOT post (shouldShareKeys=false from
-- senderKey == selfKey). The other 3 still post.
-- ----------------------------------------------------------------------
local function ScenarioSelfEchoOneMatching()
  print("\n========== Scenario 3: self-echo on peer3 only ==========")

  local sender = BuildSender({ name = "Healer", realm = "RealmB", inInstance = true })
  local peers = {
    BuildPeer({ name = "Leader", realm = "RealmA", inInstance = true }),
    BuildPeer({ name = "Tank", realm = "RealmC", inInstance = true }),
    BuildPeer({ name = "Healer", realm = "RealmB", inInstance = true }), -- matches sender
    BuildPeer({ name = "Dps1", realm = "RealmD", inInstance = true }),
  }

  for _, peer in ipairs(peers) do
    peer.dispatch(sender.bytes.prefix, sender.bytes.message, sender.bytes.channel, "Healer-RealmB")
  end

  Check(#peers[1].chatMessages == 1, "Leader (different ID) emitted 1 chat")
  Check(#peers[2].chatMessages == 1, "Tank (different ID) emitted 1 chat")
  Check(#peers[3].chatMessages == 0, "Healer (== sender ID) emitted NO chat (self-echo guard)")
  Check(peers[3].sendOwnKeystoneCalls == 0, "Healer did not even call sendOwnKeystoneToChat")
  Check(#peers[4].chatMessages == 1, "Dps1 (different ID) emitted 1 chat")
end

-- ----------------------------------------------------------------------
-- Scenario 4: re-trigger after cooldown expires. Sender sends SHAREKEYS
-- twice with 35s between. All peers post once on first send, once on
-- second send (cooldown of 30s expired between).
-- ----------------------------------------------------------------------
local function ScenarioReTriggerAfterCooldownExpires()
  print("\n========== Scenario 4: re-trigger after 35s — both pass for all ==========")

  local sender = BuildSender({ name = "Leader", realm = "RealmA", inInstance = true })
  local peers = {
    BuildPeer({ name = "Healer", realm = "RealmB", inInstance = true, now = 1000 }),
    BuildPeer({ name = "Tank", realm = "RealmC", inInstance = true, now = 1000 }),
    BuildPeer({ name = "Dps1", realm = "RealmD", inInstance = true, now = 1000 }),
    BuildPeer({ name = "Dps2", realm = "RealmE", inInstance = true, now = 1000 }),
  }

  for _, peer in ipairs(peers) do
    peer.dispatch(sender.bytes.prefix, sender.bytes.message, sender.bytes.channel, "Leader-RealmA")
    peer.advanceTime(35)
    peer.dispatch(sender.bytes.prefix, sender.bytes.message, sender.bytes.channel, "Leader-RealmA")
  end

  for i, peer in ipairs(peers) do
    Check(#peer.chatMessages == 2, string.format("peer #%d (%s) emitted 2 chats across both triggers", i, peer.name))
    Check(peer.cooldownAborts == 0, string.format("peer #%d (%s) had no cooldown abort across 35s gap", i, peer.name))
  end
end

-- ----------------------------------------------------------------------
-- Scenario 5: re-trigger within cooldown — only first emits chat.
-- ----------------------------------------------------------------------
local function ScenarioReTriggerWithinCooldown()
  print("\n========== Scenario 5: re-trigger within 5s — only first emits ==========")

  local sender = BuildSender({ name = "Leader", realm = "RealmA", inInstance = true })
  local peers = {
    BuildPeer({ name = "Healer", realm = "RealmB", inInstance = true, now = 1000 }),
    BuildPeer({ name = "Tank", realm = "RealmC", inInstance = true, now = 1000 }),
    BuildPeer({ name = "Dps1", realm = "RealmD", inInstance = true, now = 1000 }),
    BuildPeer({ name = "Dps2", realm = "RealmE", inInstance = true, now = 1000 }),
  }

  for _, peer in ipairs(peers) do
    peer.dispatch(sender.bytes.prefix, sender.bytes.message, sender.bytes.channel, "Leader-RealmA")
    peer.advanceTime(5)
    peer.dispatch(sender.bytes.prefix, sender.bytes.message, sender.bytes.channel, "Leader-RealmA")
  end

  for i, peer in ipairs(peers) do
    Check(
      #peer.chatMessages == 1,
      string.format("peer #%d (%s) emitted exactly 1 chat (second was cooldown-blocked)", i, peer.name)
    )
    Check(peer.cooldownAborts == 1, string.format("peer #%d (%s) cooldown-aborted exactly once", i, peer.name))
  end
end

ScenarioConvergence4Receivers()
ScenarioCooldownIsolation()
ScenarioSelfEchoOneMatching()
ScenarioReTriggerAfterCooldownExpires()
ScenarioReTriggerWithinCooldown()

if failures > 0 then
  print(string.format("\nMulti-peer convergence simulator failed: %d check(s) failed", failures))
  os.exit(1)
end

print("\nMulti-peer convergence simulator passed.")
