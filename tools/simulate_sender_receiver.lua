-- Standalone CLI tool: uses standard Lua globals outside the WoW runtime.
---@diagnostic disable-next-line: undefined-global
local io = io
---@diagnostic disable-next-line: undefined-global
local load = load

local function LoadLocal(path)
  local file = assert(io.open(path, "rb"))
  local source = file:read("*a")
  file:close()
  local chunk, err = load(source, "@" .. path)
  assert(chunk, err)
  return chunk()
end

local Harness = LoadLocal("testmodul/isilive_test_harness.lua")
local Fixtures = LoadLocal("testmodul/isilive_test_fixtures.lua")

local function BuildStrsplit()
  return function(sep, str, max)
    local pos = str:find(sep, 1, true)
    if not pos then
      return str
    end
    if max and max >= 2 then
      return str:sub(1, pos - 1), str:sub(pos + 1)
    end
    return str:sub(1, pos - 1)
  end
end

local function WithSyncGlobals(fn, opts)
  opts = opts or {}
  Harness.WithGlobals({
    GetRealmName = function()
      return opts.realm or "Realm"
    end,
    GetTime = function()
      return opts.now or 100
    end,
    IsInGroup = function()
      return opts.inGroup ~= false
    end,
    IsInRaid = function()
      return opts.inRaid == true
    end,
    strsplit = BuildStrsplit(),
    C_ChatInfo = opts.chatInfo,
  }, fn)
end

local function LoadSync()
  return Harness.LoadAddonModules({ "isiLive_sync.lua" })
end

local function PrintTable(prefix, t)
  if type(t) ~= "table" then
    print(prefix .. tostring(t))
    return
  end
  local parts = {}
  for key, value in pairs(t) do
    parts[#parts + 1] = string.format("%s=%s", tostring(key), tostring(value))
  end
  table.sort(parts)
  print(prefix .. table.concat(parts, ", "))
end

local function SimulateShareKeys()
  local sent = {}
  WithSyncGlobals(function()
    local addon = LoadSync()
    local ok = addon.Sync.SendShareKeysRequest()
    print("sender.sharekeys.ok=" .. tostring(ok))
  end, {
    chatInfo = {
      SendAddonMessage = function(prefix, message, channel)
        sent[#sent + 1] = {
          prefix = prefix,
          message = message,
          channel = channel,
        }
        return true
      end,
    },
  })

  WithSyncGlobals(function()
    local addon = LoadSync()
    local result = addon.Sync.ProcessAddonMessage(
      sent[1].prefix,
      sent[1].message,
      "OtherPlayer-OtherRealm",
      "Me",
      "Realm",
      sent[1].channel
    )
    PrintTable("receiver.sharekeys.", result)
  end, {})
end

local function SimulateKey()
  WithSyncGlobals(function()
    local addon = LoadSync()
    local result = addon.Sync.ProcessAddonMessage("ISILIVE", "KEY:2649:15:100:local", "Peer-OtherRealm", "Me", "Realm")
    PrintTable("receiver.key.", result)
    PrintTable("receiver.key.state.", addon.Sync.GetPlayerKeyInfo("Peer", "OtherRealm"))
  end, {})
end

local function SimulateStats()
  WithSyncGlobals(function()
    local addon = LoadSync()
    local result =
      addon.Sync.ProcessAddonMessage("ISILIVE", "STATS:72:615:3210:100:local", "Peer-OtherRealm", "Me", "Realm")
    PrintTable("receiver.stats.", result)
    PrintTable("receiver.stats.state.", addon.Sync.GetPlayerStatsInfo("Peer", "OtherRealm"))
  end, {})
end

local function SimulateKick()
  WithSyncGlobals(function()
    local addon = LoadSync()
    local result = addon.Sync.ProcessAddonMessage("ISILIVE", "KICK:1:8", "Peer-OtherRealm", "Me", "Realm")
    PrintTable("receiver.kick.", result)
    PrintTable("receiver.kick.state.", addon.Sync.GetPlayerKickInfo("Peer", "OtherRealm"))
  end, {})
end

local function SimulateShareKeysEventHandler()
  local counts = {
    keystoneChatShares = 0,
    cooldownTriggers = 0,
  }

  local addon = nil
  local controller = nil

  WithSyncGlobals(function()
    addon = Harness.LoadAddonModules({ "isiLive_sync.lua", "isiLive_event_handlers.lua" })
    controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, {}, {
      isMainFrameShown = function()
        return false
      end,
      processAddonMessage = function(prefix, message, sender, _localName, _localRealm, channel)
        return addon.Sync.ProcessAddonMessage(prefix, message, sender, "Me", "Realm", channel)
      end,
      sendOwnKeystoneToChat = function()
        counts.keystoneChatShares = counts.keystoneChatShares + 1
        return true
      end,
      triggerShareKeysCooldown = function()
        counts.cooldownTriggers = counts.cooldownTriggers + 1
      end,
    })

    controller:Dispatch("CHAT_MSG_ADDON", addon.Sync.GetPrefix(), "SHAREKEYS", "PARTY", "OtherPlayer-OtherRealm")
  end, {
    chatInfo = {
      SendAddonMessage = function()
        return true
      end,
    },
  })

  PrintTable("event.sharekeys.counts.", counts)
end

local mode = tostring((...)) or "all"
if mode == "sharekeys" then
  SimulateShareKeys()
elseif mode == "key" then
  SimulateKey()
elseif mode == "stats" then
  SimulateStats()
elseif mode == "kick" then
  SimulateKick()
elseif mode == "event" then
  SimulateShareKeysEventHandler()
else
  SimulateShareKeys()
  SimulateKey()
  SimulateStats()
  SimulateKick()
  SimulateShareKeysEventHandler()
end
