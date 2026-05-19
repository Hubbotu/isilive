local function RegisterHiddenFrameBasicSyncTests(test, Assert, LoadAddonModules, Fixtures)
  test("Event handlers pre-render UI for hidden addon sync updates", function()
    local counters = { uiUpdates = 0 }
    local roster = {
      { name = "Alpha", realm = "RealmA", hasIsiLive = false },
    }

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
      isMainFrameShown = function()
        return false
      end,
      processAddonMessage = function(_prefix, _message, _sender)
        return { shouldAck = false }
      end,
      forEachRosterInfo = function(visitor)
        for _, info in ipairs(roster) do
          visitor(info)
        end
      end,
      isSyncUserKnown = function(name, _realm)
        return name == "Alpha"
      end,
    })

    controller:Dispatch("CHAT_MSG_ADDON", "ISI_SYNC", "hello", "PARTY", "Alpha-RealmA")

    Assert.True(roster[1].hasIsiLive, "hidden sync handling must still update background roster state")
    Assert.Equal(counters.uiUpdates, 1, "hidden sync handling should pre-render UI state once")
  end)

  test("Event handlers answer refresh requests while frame is hidden", function()
    local counters = { uiUpdates = 0, refreshResponses = 0 }
    local targetSnapshots = 0
    local kickReplies = 0

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
      isMainFrameShown = function()
        return false
      end,
      processAddonMessage = function(_prefix, _message, _sender)
        return { shouldAck = false, shouldRequestRefresh = true }
      end,
      sendOwnTargetSnapshot = function(force, source, allowHidden)
        if force and source == "reqsync" and allowHidden == true then
          targetSnapshots = targetSnapshots + 1
        end
      end,
      sendOwnKickState = function()
        kickReplies = kickReplies + 1
      end,
    })

    controller:Dispatch("CHAT_MSG_ADDON", "ISI_SYNC", "REQSYNC", "PARTY", "Alpha-RealmA")

    Assert.Equal(counters.refreshResponses, 1, "hidden refresh requests must trigger one sync response")
    Assert.Equal(targetSnapshots, 1, "hidden refresh requests must also trigger one exact target snapshot")
    Assert.Equal(kickReplies, 1, "hidden refresh requests must also trigger one kick-state snapshot")
    Assert.Equal(counters.uiUpdates, 0, "answering a hidden refresh request must not force a UI redraw by itself")
  end)

  test("Event handlers answer LibKeystone requests while frame is hidden", function()
    local counters = { uiUpdates = 0, refreshResponses = 0 }
    local libKeystoneReplies = 0

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
      isMainFrameShown = function()
        return false
      end,
      processAddonMessage = function(_prefix, _message, _sender, _channel)
        return { shouldReplyLibKeystone = true }
      end,
      sendLibKeystonePartyData = function(force)
        if force == true then
          libKeystoneReplies = libKeystoneReplies + 1
          return true
        end
        return false
      end,
    })

    controller:Dispatch("CHAT_MSG_ADDON", "LibKS", "R", "PARTY", "Alpha-RealmA")

    Assert.Equal(libKeystoneReplies, 1, "hidden LibKeystone requests must trigger one party-key reply")
    Assert.Equal(counters.refreshResponses, 0, "LibKeystone requests must not trigger isiLive refresh replies")
    Assert.Equal(counters.uiUpdates, 0, "answering a hidden LibKeystone request must not force a UI redraw")
  end)
end

local function RegisterHiddenFrameRealParserKeyTests(test, Assert, LoadAddonModules, Fixtures)
  test("Event handlers process LibKeystone requests through the real sync parser and refresh hidden state", function()
    local counters = { uiUpdates = 0, refreshResponses = 0 }
    local libKeystoneReplies = 0
    local roster = {
      { name = "Alpha", realm = "RealmA", hasIsiLive = false },
    }

    local function WithSyncGlobals(fn)
      local previous = {
        GetRealmName = rawget(_G, "GetRealmName"),
        IsInRaid = rawget(_G, "IsInRaid"),
        IsInGroup = rawget(_G, "IsInGroup"),
        IsiLiveDB = rawget(_G, "IsiLiveDB"),
        GetSpecializationInfoByID = rawget(_G, "GetSpecializationInfoByID"),
      }
      local previousStrsplit = rawget(_G, "strsplit")
      _G.GetRealmName = function()
        return "Realm"
      end
      _G.IsInRaid = function()
        return false
      end
      _G.IsInGroup = function()
        return true
      end
      _G.IsiLiveDB = { syncEnabled = true }
      _G.GetSpecializationInfoByID = function(specID)
        if specID == 265 then
          return nil, "Affliction"
        end
        return nil, nil
      end
      local function Strsplit(sep, str, max)
        local pos = str:find(sep, 1, true)
        if not pos then
          return str
        end
        if max and max >= 2 then
          return str:sub(1, pos - 1), str:sub(pos + 1)
        end
        return str:sub(1, pos - 1)
      end
      rawset(_G, "strsplit", Strsplit)
      local ok, err = pcall(fn)
      rawset(_G, "strsplit", previousStrsplit)
      _G.GetRealmName = previous.GetRealmName
      _G.IsInRaid = previous.IsInRaid
      _G.IsInGroup = previous.IsInGroup
      _G.IsiLiveDB = previous.IsiLiveDB
      _G.GetSpecializationInfoByID = previous.GetSpecializationInfoByID
      if not ok then
        error(err, 0)
      end
    end
    WithSyncGlobals(function()
      local addon = LoadAddonModules({ "isiLive_sync.lua", "isiLive_event_handlers.lua" })
      local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
        isMainFrameShown = function()
          return false
        end,
        processAddonMessage = function(prefix, message, sender, channel)
          return addon.Sync.ProcessAddonMessage(prefix, message, sender, "Me", "Realm", channel)
        end,
        sendLibKeystonePartyData = function(force)
          if force == true then
            libKeystoneReplies = libKeystoneReplies + 1
            return true
          end
          return false
        end,
        forEachRosterInfo = function(visitor)
          for _, info in ipairs(roster) do
            visitor(info)
          end
        end,
        isSyncUserKnown = function(name, _realm)
          return name == "Alpha"
        end,
      })

      controller:Dispatch("CHAT_MSG_ADDON", "LibKS", "R", "PARTY", "Alpha-RealmA")
    end)

    Assert.Equal(libKeystoneReplies, 1, "real LibKeystone requests must trigger one party-key reply")
    Assert.Equal(roster[1].hasIsiLive, true, "real LibKeystone requests must mark known peers as isiLive-enabled")
    Assert.Equal(counters.uiUpdates, 1, "real LibKeystone requests must refresh hidden UI state once")
    Assert.Equal(counters.refreshResponses, 0, "real LibKeystone requests must not trigger isiLive refresh replies")
  end)

  test("Event handlers process KEY through the real sync parser and apply roster key data", function()
    local counters = { uiUpdates = 0, refreshResponses = 0 }
    local roster = {
      { name = "Alpha", realm = "RealmA", hasIsiLive = false, keyMapID = nil, keyLevel = nil },
    }
    local sentMessages = {}

    local function WithSyncGlobals(fn)
      local previous = {
        GetRealmName = rawget(_G, "GetRealmName"),
        IsInRaid = rawget(_G, "IsInRaid"),
        IsInGroup = rawget(_G, "IsInGroup"),
        IsiLiveDB = rawget(_G, "IsiLiveDB"),
        C_ChatInfo = rawget(_G, "C_ChatInfo"),
      }
      local previousStrsplit = rawget(_G, "strsplit")
      _G.GetRealmName = function()
        return "Realm"
      end
      _G.IsInRaid = function()
        return false
      end
      _G.IsInGroup = function()
        return true
      end
      _G.IsiLiveDB = { syncEnabled = true }
      local function Strsplit(sep, str, max)
        local pos = str:find(sep, 1, true)
        if not pos then
          return str
        end
        if max and max >= 2 then
          return str:sub(1, pos - 1), str:sub(pos + 1)
        end
        return str:sub(1, pos - 1)
      end
      rawset(_G, "strsplit", Strsplit)
      local ok, err = pcall(fn)
      rawset(_G, "strsplit", previousStrsplit)
      _G.GetRealmName = previous.GetRealmName
      _G.IsInRaid = previous.IsInRaid
      _G.IsInGroup = previous.IsInGroup
      _G.IsiLiveDB = previous.IsiLiveDB
      _G.C_ChatInfo = previous.C_ChatInfo
      if not ok then
        error(err, 0)
      end
    end
    WithSyncGlobals(function()
      _G.C_ChatInfo = {
        SendAddonMessage = function(prefix, message, channel)
          table.insert(sentMessages, {
            prefix = prefix,
            message = message,
            channel = channel,
          })
        end,
      }

      local addon = LoadAddonModules({ "isiLive_sync.lua", "isiLive_keysync.lua", "isiLive_event_handlers.lua" })
      local keysync = addon.KeySync.CreateController({
        sync = addon.Sync,
        getUnitNameAndRealm = function(_unit)
          return "Me", "Realm"
        end,
        isFrameVisible = function()
          return false
        end,
      })
      local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
        isMainFrameShown = function()
          return false
        end,
        processAddonMessage = function(prefix, message, sender, channel)
          return addon.Sync.ProcessAddonMessage(prefix, message, sender, "Me", "Realm", channel)
        end,
        applyKnownKeyToRosterEntry = function(info)
          return keysync.ApplyKnownKeyToRosterEntry(info)
        end,
        forEachRosterInfo = function(visitor)
          for _, info in ipairs(roster) do
            visitor(info)
          end
        end,
        isSyncUserKnown = function(name, _realm)
          return name == "Alpha"
        end,
      })

      controller:Dispatch("CHAT_MSG_ADDON", addon.Sync.GetPrefix(), "KEY:2441:15:123:remote", "PARTY", "Alpha-RealmA")

      local keyInfo = addon.Sync.GetPlayerKeyInfo("Alpha", "RealmA")
      Assert.NotNil(keyInfo, "real KEY sync must store peer key info")
      Assert.Equal(keyInfo.mapID, 2441, "real KEY sync must keep mapID")
      Assert.Equal(keyInfo.level, 15, "real KEY sync must keep key level")
    end)

    Assert.Equal(roster[1].keyMapID, 2441, "real KEY sync must apply roster key mapID")
    Assert.Equal(roster[1].keyLevel, 15, "real KEY sync must apply roster key level")
    Assert.Equal(roster[1].hasIsiLive, true, "real KEY sync must mark known peers as isiLive-enabled")
    Assert.Equal(counters.uiUpdates, 1, "real KEY sync must refresh hidden UI state once")
    Assert.Equal(counters.refreshResponses, 0, "real KEY sync must not trigger a refresh response")
  end)
end

local function RegisterHiddenFrameRealParserStatsTests(test, Assert, LoadAddonModules, Fixtures)
  test("Event handlers process TARGET through the real sync parser and refresh target UI", function()
    local counters = { uiUpdates = 0, refreshResponses = 0, updates = 0 }
    local statusUpdates = 0

    local function WithSyncGlobals(fn)
      local previous = {
        GetRealmName = rawget(_G, "GetRealmName"),
        IsInRaid = rawget(_G, "IsInRaid"),
        IsInGroup = rawget(_G, "IsInGroup"),
        IsiLiveDB = rawget(_G, "IsiLiveDB"),
      }
      local previousStrsplit = rawget(_G, "strsplit")
      _G.GetRealmName = function()
        return "Realm"
      end
      _G.IsInRaid = function()
        return false
      end
      _G.IsInGroup = function()
        return true
      end
      _G.IsiLiveDB = { syncEnabled = true }
      local function Strsplit(sep, str, max)
        local pos = str:find(sep, 1, true)
        if not pos then
          return str
        end
        if max and max >= 2 then
          return str:sub(1, pos - 1), str:sub(pos + 1)
        end
        return str:sub(1, pos - 1)
      end
      rawset(_G, "strsplit", Strsplit)
      local ok, err = pcall(fn)
      rawset(_G, "strsplit", previousStrsplit)
      _G.GetRealmName = previous.GetRealmName
      _G.IsInRaid = previous.IsInRaid
      _G.IsInGroup = previous.IsInGroup
      _G.IsiLiveDB = previous.IsiLiveDB
      if not ok then
        error(err, 0)
      end
    end
    WithSyncGlobals(function()
      local addon = LoadAddonModules({ "isiLive_sync.lua", "isiLive_event_handlers.lua" })
      local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
        isMainFrameShown = function()
          return false
        end,
        processAddonMessage = function(prefix, message, sender, channel)
          return addon.Sync.ProcessAddonMessage(prefix, message, sender, "Me", "Realm", channel)
        end,
        updateStatusLine = function()
          statusUpdates = statusUpdates + 1
        end,
      })

      controller:Dispatch(
        "CHAT_MSG_ADDON",
        addon.Sync.GetPrefix(),
        "TARGET:2441:14:123:remote",
        "PARTY",
        "Alpha-RealmA"
      )

      local targetInfo = addon.Sync.GetPlayerTargetInfo("Alpha", "RealmA")
      Assert.NotNil(targetInfo, "real TARGET sync must store peer target info")
      Assert.Equal(targetInfo.mapID, 2441, "real TARGET sync must keep mapID")
      Assert.Equal(targetInfo.level, 14, "real TARGET sync must keep target level")
      Assert.Equal(targetInfo.source, "remote", "real TARGET sync must keep source metadata")
    end)

    Assert.Equal(statusUpdates, 1, "real TARGET sync must refresh the status line once")
    Assert.Equal(counters.updates, 1, "real TARGET sync must refresh the teleport highlight once")
    Assert.Equal(counters.uiUpdates, 1, "real TARGET sync must refresh the hidden UI once")
    Assert.Equal(counters.refreshResponses, 0, "real TARGET sync must not trigger a refresh response")
  end)

  test("Event handlers process STATS through the real sync parser and backfill roster stats", function()
    local counters = { uiUpdates = 0, refreshResponses = 0 }
    local roster = {
      { name = "Alpha", realm = "RealmA", hasIsiLive = false, spec = nil, ilvl = nil, rio = nil },
    }
    local statusUpdates = 0

    local function WithSyncGlobals(fn)
      local previous = {
        GetRealmName = rawget(_G, "GetRealmName"),
        IsInRaid = rawget(_G, "IsInRaid"),
        IsInGroup = rawget(_G, "IsInGroup"),
        IsiLiveDB = rawget(_G, "IsiLiveDB"),
      }
      local previousStrsplit = rawget(_G, "strsplit")
      _G.GetRealmName = function()
        return "Realm"
      end
      _G.IsInRaid = function()
        return false
      end
      _G.IsInGroup = function()
        return true
      end
      _G.IsiLiveDB = { syncEnabled = true }
      local function Strsplit(sep, str, max)
        local pos = str:find(sep, 1, true)
        if not pos then
          return str
        end
        if max and max >= 2 then
          return str:sub(1, pos - 1), str:sub(pos + 1)
        end
        return str:sub(1, pos - 1)
      end
      rawset(_G, "strsplit", Strsplit)
      local ok, err = pcall(fn)
      rawset(_G, "strsplit", previousStrsplit)
      _G.GetRealmName = previous.GetRealmName
      _G.IsInRaid = previous.IsInRaid
      _G.IsInGroup = previous.IsInGroup
      _G.IsiLiveDB = previous.IsiLiveDB
      if not ok then
        error(err, 0)
      end
    end
    WithSyncGlobals(function()
      local addon = LoadAddonModules({ "isiLive_sync.lua", "isiLive_keysync.lua", "isiLive_event_handlers.lua" })
      local keysync = addon.KeySync.CreateController({
        sync = addon.Sync,
        getUnitNameAndRealm = function(_unit)
          return "Me", "Realm"
        end,
        isFrameVisible = function()
          return false
        end,
      })
      local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
        isMainFrameShown = function()
          return false
        end,
        processAddonMessage = function(prefix, message, sender, channel)
          return addon.Sync.ProcessAddonMessage(prefix, message, sender, "Me", "Realm", channel)
        end,
        applyKnownKeyToRosterEntry = function(info)
          return keysync.ApplyKnownKeyToRosterEntry(info)
        end,
        forEachRosterInfo = function(visitor)
          for _, info in ipairs(roster) do
            visitor(info)
          end
        end,
        isSyncUserKnown = function(name, _realm)
          return name == "Alpha"
        end,
        updateStatusLine = function()
          statusUpdates = statusUpdates + 1
        end,
      })

      controller:Dispatch(
        "CHAT_MSG_ADDON",
        addon.Sync.GetPrefix(),
        "STATS:265:630:3400:123:remote",
        "PARTY",
        "Alpha-RealmA"
      )

      local statsInfo = addon.Sync.GetPlayerStatsInfo("Alpha", "RealmA")
      Assert.NotNil(statsInfo, "real STATS sync must store peer stats info")
      Assert.Equal(statsInfo.specID, 265, "real STATS sync must keep specID")
      Assert.Equal(statsInfo.ilvl, 630, "real STATS sync must keep ilvl")
      Assert.Equal(statsInfo.rio, 3400, "real STATS sync must keep rio")
    end)

    Assert.Equal(roster[1].hasIsiLive, true, "real STATS sync must mark known peers as isiLive-enabled")
    Assert.Equal(roster[1].ilvl, 630, "real STATS sync must backfill ilvl")
    Assert.Equal(roster[1].rio, 3400, "real STATS sync must backfill rio")
    Assert.Equal(statusUpdates, 1, "real STATS sync must refresh the status line once")
    Assert.Equal(counters.uiUpdates, 1, "real STATS sync must refresh the hidden UI once")
    Assert.Equal(counters.refreshResponses, 0, "real STATS sync must not trigger a refresh response")
  end)
end

local function RegisterHiddenFrameRealParserDpsLocTests(test, Assert, LoadAddonModules, Fixtures)
  test("Event handlers process DPS through the real sync parser and backfill roster DPS", function()
    local counters = { uiUpdates = 0, refreshResponses = 0 }
    local roster = {
      { name = "Alpha", realm = "RealmA", hasIsiLive = false, syncDps = nil },
    }

    local function WithSyncGlobals(fn)
      local previous = {
        GetRealmName = rawget(_G, "GetRealmName"),
        IsInRaid = rawget(_G, "IsInRaid"),
        IsInGroup = rawget(_G, "IsInGroup"),
        IsiLiveDB = rawget(_G, "IsiLiveDB"),
      }
      local previousStrsplit = rawget(_G, "strsplit")
      _G.GetRealmName = function()
        return "Realm"
      end
      _G.IsInRaid = function()
        return false
      end
      _G.IsInGroup = function()
        return true
      end
      _G.IsiLiveDB = { syncEnabled = true }
      local function Strsplit(sep, str, max)
        local pos = str:find(sep, 1, true)
        if not pos then
          return str
        end
        if max and max >= 2 then
          return str:sub(1, pos - 1), str:sub(pos + 1)
        end
        return str:sub(1, pos - 1)
      end
      rawset(_G, "strsplit", Strsplit)
      local ok, err = pcall(fn)
      rawset(_G, "strsplit", previousStrsplit)
      _G.GetRealmName = previous.GetRealmName
      _G.IsInRaid = previous.IsInRaid
      _G.IsInGroup = previous.IsInGroup
      _G.IsiLiveDB = previous.IsiLiveDB
      if not ok then
        error(err, 0)
      end
    end
    WithSyncGlobals(function()
      local addon = LoadAddonModules({ "isiLive_sync.lua", "isiLive_keysync.lua", "isiLive_event_handlers.lua" })
      local keysync = addon.KeySync.CreateController({
        sync = addon.Sync,
        getUnitNameAndRealm = function(_unit)
          return "Me", "Realm"
        end,
        isFrameVisible = function()
          return false
        end,
      })
      local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
        isMainFrameShown = function()
          return false
        end,
        processAddonMessage = function(prefix, message, sender, channel)
          return addon.Sync.ProcessAddonMessage(prefix, message, sender, "Me", "Realm", channel)
        end,
        applyKnownKeyToRosterEntry = function(info)
          return keysync.ApplyKnownKeyToRosterEntry(info)
        end,
        forEachRosterInfo = function(visitor)
          for _, info in ipairs(roster) do
            visitor(info)
          end
        end,
        isSyncUserKnown = function(name, _realm)
          return name == "Alpha"
        end,
      })

      controller:Dispatch("CHAT_MSG_ADDON", addon.Sync.GetPrefix(), "DPS:321100:123:remote", "PARTY", "Alpha-RealmA")

      local dpsInfo = addon.Sync.GetPlayerDpsInfo("Alpha", "RealmA")
      Assert.NotNil(dpsInfo, "real DPS sync must store peer DPS info")
      Assert.Equal(dpsInfo.dps, 321100, "real DPS sync must keep the DPS value")
      Assert.Equal(dpsInfo.source, "remote", "real DPS sync must keep source metadata")
    end)

    Assert.Equal(roster[1].hasIsiLive, true, "real DPS sync must mark known peers as isiLive-enabled")
    Assert.Equal(roster[1].syncDps, 321100, "real DPS sync must backfill roster DPS")
    Assert.Equal(counters.uiUpdates, 1, "real DPS sync must refresh the hidden UI once")
    Assert.Equal(counters.refreshResponses, 0, "real DPS sync must not trigger a refresh response")
  end)

  test("Event handlers process LOC through the real sync parser and backfill roster location", function()
    local counters = { uiUpdates = 0, refreshResponses = 0 }
    local roster = {
      { name = "Alpha", realm = "RealmA", hasIsiLive = false, syncLocMapID = nil },
    }

    local function WithSyncGlobals(fn)
      local previous = {
        GetRealmName = rawget(_G, "GetRealmName"),
        IsInRaid = rawget(_G, "IsInRaid"),
        IsInGroup = rawget(_G, "IsInGroup"),
        IsiLiveDB = rawget(_G, "IsiLiveDB"),
      }
      local previousStrsplit = rawget(_G, "strsplit")
      _G.GetRealmName = function()
        return "Realm"
      end
      _G.IsInRaid = function()
        return false
      end
      _G.IsInGroup = function()
        return true
      end
      _G.IsiLiveDB = { syncEnabled = true }
      local function Strsplit(sep, str, max)
        local pos = str:find(sep, 1, true)
        if not pos then
          return str
        end
        if max and max >= 2 then
          return str:sub(1, pos - 1), str:sub(pos + 1)
        end
        return str:sub(1, pos - 1)
      end
      rawset(_G, "strsplit", Strsplit)
      local ok, err = pcall(fn)
      rawset(_G, "strsplit", previousStrsplit)
      _G.GetRealmName = previous.GetRealmName
      _G.IsInRaid = previous.IsInRaid
      _G.IsInGroup = previous.IsInGroup
      _G.IsiLiveDB = previous.IsiLiveDB
      if not ok then
        error(err, 0)
      end
    end
    WithSyncGlobals(function()
      local addon = LoadAddonModules({ "isiLive_sync.lua", "isiLive_keysync.lua", "isiLive_event_handlers.lua" })
      local keysync = addon.KeySync.CreateController({
        sync = addon.Sync,
        getUnitNameAndRealm = function(_unit)
          return "Me", "Realm"
        end,
        isFrameVisible = function()
          return false
        end,
      })
      local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
        isMainFrameShown = function()
          return false
        end,
        processAddonMessage = function(prefix, message, sender, channel)
          return addon.Sync.ProcessAddonMessage(prefix, message, sender, "Me", "Realm", channel)
        end,
        applyKnownKeyToRosterEntry = function(info)
          return keysync.ApplyKnownKeyToRosterEntry(info)
        end,
        forEachRosterInfo = function(visitor)
          for _, info in ipairs(roster) do
            visitor(info)
          end
        end,
        isSyncUserKnown = function(name, _realm)
          return name == "Alpha"
        end,
      })

      controller:Dispatch("CHAT_MSG_ADDON", addon.Sync.GetPrefix(), "LOC:2649:123:remote", "PARTY", "Alpha-RealmA")

      local locInfo = addon.Sync.GetPlayerLocInfo("Alpha", "RealmA")
      Assert.NotNil(locInfo, "real LOC sync must store peer location info")
      Assert.Equal(locInfo.mapID, 2649, "real LOC sync must keep the mapID")
      Assert.Equal(locInfo.source, "remote", "real LOC sync must keep source metadata")
    end)

    Assert.Equal(roster[1].hasIsiLive, true, "real LOC sync must mark known peers as isiLive-enabled")
    Assert.Equal(roster[1].syncLocMapID, 2649, "real LOC sync must backfill roster location mapID")
    Assert.Equal(counters.uiUpdates, 1, "real LOC sync must refresh the hidden UI once")
    Assert.Equal(counters.refreshResponses, 0, "real LOC sync must not trigger a refresh response")
  end)
end

local function RegisterHiddenFrameShareKeysAndReqSyncTests(test, Assert, LoadAddonModules, Fixtures)
  test("Event handlers answer SHAREKEYS requests while frame is hidden", function()
    local counters = { uiUpdates = 0, refreshResponses = 0 }
    local keystoneChatShares = 0
    local cooldownTriggers = 0

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
      isMainFrameShown = function()
        return false
      end,
      processAddonMessage = function(_prefix, _message, _sender)
        return { shouldAck = false, shouldShareKeys = true }
      end,
      sendOwnKeystoneToChat = function()
        keystoneChatShares = keystoneChatShares + 1
        return true
      end,
      triggerShareKeysCooldown = function()
        cooldownTriggers = cooldownTriggers + 1
      end,
    })

    controller:Dispatch("CHAT_MSG_ADDON", "ISI_SYNC", "SHAREKEYS", "PARTY", "Alpha-RealmA")

    Assert.Equal(keystoneChatShares, 1, "hidden SHAREKEYS must trigger one own-key chat announcement")
    Assert.Equal(cooldownTriggers, 1, "SHAREKEYS must lock the local share-keys button on all clients")
    Assert.Equal(counters.refreshResponses, 0, "SHAREKEYS must not trigger a refresh response")
    Assert.Equal(counters.uiUpdates, 0, "hidden SHAREKEYS must not force a UI redraw by itself")
  end)

  test("Event handlers skip SHAREKEYS cooldown when no own key chat share was posted", function()
    local counters = { uiUpdates = 0, refreshResponses = 0 }
    local keystoneChatShares = 0
    local cooldownTriggers = 0

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
      isMainFrameShown = function()
        return false
      end,
      processAddonMessage = function(_prefix, _message, _sender)
        return { shouldAck = false, shouldShareKeys = true }
      end,
      sendOwnKeystoneToChat = function()
        keystoneChatShares = keystoneChatShares + 1
        return false
      end,
      triggerShareKeysCooldown = function()
        cooldownTriggers = cooldownTriggers + 1
      end,
    })

    controller:Dispatch("CHAT_MSG_ADDON", "ISI_SYNC", "SHAREKEYS", "PARTY", "Alpha-RealmA")

    Assert.Equal(keystoneChatShares, 1, "hidden SHAREKEYS must still try one own-key chat announcement")
    Assert.Equal(
      cooldownTriggers,
      0,
      "SHAREKEYS must not lock the local share-keys button when no own party-key share was posted"
    )
    Assert.Equal(counters.refreshResponses, 0, "SHAREKEYS must not trigger a refresh response")
    Assert.Equal(counters.uiUpdates, 0, "hidden SHAREKEYS must not force a UI redraw by itself")
  end)

  test("Event handlers process SHAREKEYS through the real sync parser and trigger cooldown", function()
    local counters = { uiUpdates = 0, refreshResponses = 0 }
    local keystoneChatShares = 0
    local cooldownTriggers = 0
    local logs = {}

    local function WithSyncGlobals(fn)
      local previous = {
        GetRealmName = rawget(_G, "GetRealmName"),
        IsInRaid = rawget(_G, "IsInRaid"),
        IsInGroup = rawget(_G, "IsInGroup"),
        IsiLiveDB = rawget(_G, "IsiLiveDB"),
      }
      local previousStrsplit = rawget(_G, "strsplit")
      _G.GetRealmName = function()
        return "Realm"
      end
      _G.IsInRaid = function()
        return false
      end
      _G.IsInGroup = function()
        return true
      end
      _G.IsiLiveDB = { syncEnabled = true }
      local function Strsplit(sep, str, max)
        local pos = str:find(sep, 1, true)
        if not pos then
          return str
        end
        if max and max >= 2 then
          return str:sub(1, pos - 1), str:sub(pos + 1)
        end
        return str:sub(1, pos - 1)
      end
      rawset(_G, "strsplit", Strsplit)
      local ok, err = pcall(fn)
      rawset(_G, "strsplit", previousStrsplit)
      _G.GetRealmName = previous.GetRealmName
      _G.IsInRaid = previous.IsInRaid
      _G.IsInGroup = previous.IsInGroup
      _G.IsiLiveDB = previous.IsiLiveDB
      if not ok then
        error(err, 0)
      end
    end
    WithSyncGlobals(function()
      local addon = LoadAddonModules({ "isiLive_sync.lua", "isiLive_event_handlers.lua" })
      local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
        isMainFrameShown = function()
          return false
        end,
        processAddonMessage = function(prefix, message, sender, channel)
          return addon.Sync.ProcessAddonMessage(prefix, message, sender, "Me", "Realm", channel)
        end,
        sendOwnKeystoneToChat = function()
          keystoneChatShares = keystoneChatShares + 1
          return true
        end,
        triggerShareKeysCooldown = function()
          cooldownTriggers = cooldownTriggers + 1
        end,
        logRuntimeTracef = function(formatText, ...)
          logs[#logs + 1] = string.format(formatText, ...)
        end,
      })

      controller:Dispatch("CHAT_MSG_ADDON", addon.Sync.GetPrefix(), "SHAREKEYS", "PARTY", "OtherPlayer-OtherRealm")
    end)

    Assert.Equal(keystoneChatShares, 1, "real SHAREKEYS sync must trigger one own-key chat announcement")
    Assert.Equal(cooldownTriggers, 1, "real SHAREKEYS sync must lock the local share-keys button")
    Assert.Equal(counters.refreshResponses, 0, "real SHAREKEYS sync must not trigger a refresh response")
    Assert.Equal(counters.uiUpdates, 0, "real SHAREKEYS sync must not force a UI redraw by itself")
    Assert.Equal(
      logs[1],
      "[SHAREKEYS] received sender=OtherPlayer-OtherRealm",
      "real SHAREKEYS sync must log the triggering sender"
    )
    Assert.Equal(
      logs[2],
      "[SHAREKEYS] reply_result sender=OtherPlayer-OtherRealm sent=true",
      "real SHAREKEYS sync must log the local reply result"
    )
    Assert.Equal(
      logs[3],
      "[SHAREKEYS] cooldown_triggered sender=OtherPlayer-OtherRealm",
      "real SHAREKEYS sync must log the cooldown side effect"
    )
  end)

  test("Event handlers process REQSYNC through the real sync parser and answer hidden refreshes", function()
    local counters = { uiUpdates = 0, refreshResponses = 0 }
    local helloReplies = 0
    local targetSnapshots = 0
    local kickReplies = 0
    local ackReplies = 0

    local function WithSyncGlobals(fn)
      local previous = {
        GetRealmName = rawget(_G, "GetRealmName"),
        IsInRaid = rawget(_G, "IsInRaid"),
        IsInGroup = rawget(_G, "IsInGroup"),
        IsiLiveDB = rawget(_G, "IsiLiveDB"),
      }
      local previousStrsplit = rawget(_G, "strsplit")
      _G.GetRealmName = function()
        return "Realm"
      end
      _G.IsInRaid = function()
        return false
      end
      _G.IsInGroup = function()
        return true
      end
      _G.IsiLiveDB = { syncEnabled = true }
      local function Strsplit(sep, str, max)
        local pos = str:find(sep, 1, true)
        if not pos then
          return str
        end
        if max and max >= 2 then
          return str:sub(1, pos - 1), str:sub(pos + 1)
        end
        return str:sub(1, pos - 1)
      end
      rawset(_G, "strsplit", Strsplit)
      local ok, err = pcall(fn)
      rawset(_G, "strsplit", previousStrsplit)
      _G.GetRealmName = previous.GetRealmName
      _G.IsInRaid = previous.IsInRaid
      _G.IsInGroup = previous.IsInGroup
      _G.IsiLiveDB = previous.IsiLiveDB
      if not ok then
        error(err, 0)
      end
    end
    WithSyncGlobals(function()
      local addon = LoadAddonModules({ "isiLive_sync.lua", "isiLive_event_handlers.lua" })
      local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
        isMainFrameShown = function()
          return false
        end,
        processAddonMessage = function(prefix, message, sender, channel)
          return addon.Sync.ProcessAddonMessage(prefix, message, sender, "Me", "Realm", channel)
        end,
        sendIsiLiveHello = function(force, source)
          if force == true and source == "reqsync-ack" then
            helloReplies = helloReplies + 1
          end
        end,
        sendRefreshResponse = function()
          counters.refreshResponses = counters.refreshResponses + 1
          return true
        end,
        sendOwnTargetSnapshot = function(force, source, allowHidden)
          if force == true and source == "reqsync" and allowHidden == true then
            targetSnapshots = targetSnapshots + 1
          end
        end,
        sendOwnKickState = function()
          kickReplies = kickReplies + 1
        end,
        sendAck = function()
          ackReplies = ackReplies + 1
        end,
      })

      controller:Dispatch("CHAT_MSG_ADDON", addon.Sync.GetPrefix(), "REQSYNC", "PARTY", "OtherPlayer-OtherRealm")
    end)

    Assert.Equal(helloReplies, 1, "real REQSYNC sync must send one hello ack")
    Assert.Equal(counters.refreshResponses, 1, "real REQSYNC sync must trigger one refresh response")
    Assert.Equal(targetSnapshots, 1, "real REQSYNC sync must send one exact target snapshot")
    Assert.Equal(kickReplies, 1, "real REQSYNC sync must send one kick-state snapshot")
    Assert.Equal(ackReplies, 0, "real REQSYNC sync must not send a plain ack")
    Assert.Equal(counters.uiUpdates, 0, "real REQSYNC sync must not force a UI redraw by itself")
  end)
end

local function RegisterHiddenFrameKickHelloAckTests(test, Assert, LoadAddonModules, Fixtures)
  test("Event handlers process KICK through the real sync parser and refresh hidden state", function()
    local counters = { uiUpdates = 0, refreshResponses = 0 }
    local kickReplies = 0

    local function WithSyncGlobals(fn)
      local previous = {
        GetRealmName = rawget(_G, "GetRealmName"),
        IsInRaid = rawget(_G, "IsInRaid"),
        IsInGroup = rawget(_G, "IsInGroup"),
        IsiLiveDB = rawget(_G, "IsiLiveDB"),
      }
      local previousStrsplit = rawget(_G, "strsplit")
      _G.GetRealmName = function()
        return "Realm"
      end
      _G.IsInRaid = function()
        return false
      end
      _G.IsInGroup = function()
        return true
      end
      _G.IsiLiveDB = { syncEnabled = true }
      local function Strsplit(sep, str, max)
        local pos = str:find(sep, 1, true)
        if not pos then
          return str
        end
        if max and max >= 2 then
          return str:sub(1, pos - 1), str:sub(pos + 1)
        end
        return str:sub(1, pos - 1)
      end
      rawset(_G, "strsplit", Strsplit)
      local ok, err = pcall(fn)
      rawset(_G, "strsplit", previousStrsplit)
      _G.GetRealmName = previous.GetRealmName
      _G.IsInRaid = previous.IsInRaid
      _G.IsInGroup = previous.IsInGroup
      _G.IsiLiveDB = previous.IsiLiveDB
      if not ok then
        error(err, 0)
      end
    end
    WithSyncGlobals(function()
      local addon = LoadAddonModules({ "isiLive_sync.lua", "isiLive_event_handlers.lua" })
      local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
        isMainFrameShown = function()
          return false
        end,
        processAddonMessage = function(prefix, message, sender, channel)
          return addon.Sync.ProcessAddonMessage(prefix, message, sender, "Me", "Realm", channel)
        end,
        sendOwnKickState = function()
          kickReplies = kickReplies + 1
        end,
      })

      controller:Dispatch("CHAT_MSG_ADDON", addon.Sync.GetPrefix(), "KICK:1:8", "PARTY", "OtherPlayer-OtherRealm")

      local kickInfo = addon.Sync.GetPlayerKickInfo("OtherPlayer", "OtherRealm")
      Assert.NotNil(kickInfo, "real KICK sync must store peer kick state")
      Assert.True(kickInfo.hasKick, "real KICK sync must preserve hasKick=true")
      Assert.True(kickInfo.onCooldown, "real KICK sync must preserve cooldown state")
      Assert.Equal(kickInfo.cooldownRemain, 8, "real KICK sync must store the received remaining cooldown")
    end)

    Assert.Equal(kickReplies, 0, "real KICK sync must not send a local kick reply")
    Assert.Equal(counters.refreshResponses, 0, "real KICK sync must not trigger a refresh response")
    Assert.Equal(counters.uiUpdates, 1, "real KICK sync must refresh hidden UI state once")
  end)

  test("Event handlers process HELLO through the real sync parser and answer hidden onboarding", function()
    local counters = { uiUpdates = 0, refreshResponses = 0 }
    local ackReplies = 0
    local helloReplies = 0
    local targetSnapshots = 0
    local kickReplies = 0
    local roster = {
      { name = "Alpha", realm = "RealmA", hasIsiLive = false },
    }

    local function WithSyncGlobals(fn)
      local previous = {
        GetRealmName = rawget(_G, "GetRealmName"),
        IsInRaid = rawget(_G, "IsInRaid"),
        IsInGroup = rawget(_G, "IsInGroup"),
        IsiLiveDB = rawget(_G, "IsiLiveDB"),
      }
      local previousStrsplit = rawget(_G, "strsplit")
      _G.GetRealmName = function()
        return "Realm"
      end
      _G.IsInRaid = function()
        return false
      end
      _G.IsInGroup = function()
        return true
      end
      _G.IsiLiveDB = { syncEnabled = true }
      local function Strsplit(sep, str, max)
        local pos = str:find(sep, 1, true)
        if not pos then
          return str
        end
        if max and max >= 2 then
          return str:sub(1, pos - 1), str:sub(pos + 1)
        end
        return str:sub(1, pos - 1)
      end
      rawset(_G, "strsplit", Strsplit)
      local ok, err = pcall(fn)
      rawset(_G, "strsplit", previousStrsplit)
      _G.GetRealmName = previous.GetRealmName
      _G.IsInRaid = previous.IsInRaid
      _G.IsInGroup = previous.IsInGroup
      _G.IsiLiveDB = previous.IsiLiveDB
      if not ok then
        error(err, 0)
      end
    end
    WithSyncGlobals(function()
      local addon = LoadAddonModules({ "isiLive_sync.lua", "isiLive_event_handlers.lua" })
      local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
        isMainFrameShown = function()
          return false
        end,
        processAddonMessage = function(prefix, message, sender, channel)
          return addon.Sync.ProcessAddonMessage(prefix, message, sender, "Me", "Realm", channel)
        end,
        sendAck = function(sender)
          if sender == "Alpha-RealmA" then
            ackReplies = ackReplies + 1
          end
        end,
        sendIsiLiveHello = function(force, source)
          if force == true and source == "hello-ack" then
            helloReplies = helloReplies + 1
          end
        end,
        sendRefreshResponse = function()
          counters.refreshResponses = counters.refreshResponses + 1
          return true
        end,
        sendOwnTargetSnapshot = function(force, source, allowHidden)
          if force == true and source == "hello" and allowHidden == true then
            targetSnapshots = targetSnapshots + 1
          end
        end,
        sendOwnKickState = function()
          kickReplies = kickReplies + 1
        end,
        forEachRosterInfo = function(visitor)
          for _, info in ipairs(roster) do
            visitor(info)
          end
        end,
        isSyncUserKnown = function(name, _realm)
          return name == "Alpha"
        end,
      })

      controller:Dispatch(
        "CHAT_MSG_ADDON",
        addon.Sync.GetPrefix(),
        "HELLO:0.9.36:2:123:refresh",
        "PARTY",
        "Alpha-RealmA"
      )

      local helloInfo = addon.Sync.GetPlayerHelloInfo("Alpha", "RealmA")
      Assert.NotNil(helloInfo, "real HELLO sync must store peer hello info")
      Assert.Equal(helloInfo.addonVersion, "0.9.36", "real HELLO sync must keep peer addon version")
      Assert.Equal(helloInfo.protocolVersion, 2, "real HELLO sync must keep protocol version")
      Assert.Equal(helloInfo.capturedAt, 123, "real HELLO sync must keep capture timestamp")
      Assert.Equal(helloInfo.source, "refresh", "real HELLO sync must keep source metadata")
    end)

    Assert.Equal(ackReplies, 1, "real HELLO sync must send one ack reply")
    Assert.Equal(helloReplies, 1, "real HELLO sync must send one hello reply")
    Assert.Equal(counters.refreshResponses, 1, "real HELLO sync must send one refresh response")
    Assert.Equal(targetSnapshots, 1, "real HELLO sync must send one target snapshot")
    Assert.Equal(kickReplies, 1, "real HELLO sync must send one kick-state snapshot")
    Assert.Equal(roster[1].hasIsiLive, true, "real HELLO sync must mark the peer as isiLive-enabled")
    Assert.Equal(counters.uiUpdates, 1, "real HELLO sync must refresh hidden UI state once")
  end)

  test("Event handlers process ACK through the real sync parser and cache hello info", function()
    local counters = { uiUpdates = 0, refreshResponses = 0 }
    local roster = {
      { name = "Beta", realm = "RealmB", hasIsiLive = false },
    }

    local function WithSyncGlobals(fn)
      local previous = {
        GetRealmName = rawget(_G, "GetRealmName"),
        IsInRaid = rawget(_G, "IsInRaid"),
        IsInGroup = rawget(_G, "IsInGroup"),
        IsiLiveDB = rawget(_G, "IsiLiveDB"),
      }
      local previousStrsplit = rawget(_G, "strsplit")
      _G.GetRealmName = function()
        return "Realm"
      end
      _G.IsInRaid = function()
        return false
      end
      _G.IsInGroup = function()
        return true
      end
      _G.IsiLiveDB = { syncEnabled = true }
      local function Strsplit(sep, str, max)
        local pos = str:find(sep, 1, true)
        if not pos then
          return str
        end
        if max and max >= 2 then
          return str:sub(1, pos - 1), str:sub(pos + 1)
        end
        return str:sub(1, pos - 1)
      end
      rawset(_G, "strsplit", Strsplit)
      local ok, err = pcall(fn)
      rawset(_G, "strsplit", previousStrsplit)
      _G.GetRealmName = previous.GetRealmName
      _G.IsInRaid = previous.IsInRaid
      _G.IsInGroup = previous.IsInGroup
      _G.IsiLiveDB = previous.IsiLiveDB
      if not ok then
        error(err, 0)
      end
    end
    WithSyncGlobals(function()
      local addon = LoadAddonModules({ "isiLive_sync.lua", "isiLive_event_handlers.lua" })
      local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
        isMainFrameShown = function()
          return false
        end,
        processAddonMessage = function(prefix, message, sender, channel)
          return addon.Sync.ProcessAddonMessage(prefix, message, sender, "Me", "Realm", channel)
        end,
        sendAck = function()
          error("ACK sync must not send a follow-up ack")
        end,
        sendIsiLiveHello = function()
          error("ACK sync must not send a hello reply")
        end,
        sendRefreshResponse = function()
          error("ACK sync must not send a refresh response")
        end,
        sendOwnTargetSnapshot = function()
          error("ACK sync must not send a target snapshot")
        end,
        sendOwnKickState = function()
          error("ACK sync must not send a kick-state snapshot")
        end,
        forEachRosterInfo = function(visitor)
          for _, info in ipairs(roster) do
            visitor(info)
          end
        end,
        isSyncUserKnown = function(name, _realm)
          return name == "Beta"
        end,
      })

      controller:Dispatch("CHAT_MSG_ADDON", addon.Sync.GetPrefix(), "ACK:0.9.41", "PARTY", "Beta-RealmB")

      local helloInfo = addon.Sync.GetPlayerHelloInfo("Beta", "RealmB")
      Assert.NotNil(helloInfo, "real ACK sync must store peer hello info")
      Assert.Equal(helloInfo.addonVersion, "0.9.41", "real ACK sync must keep peer addon version")
      Assert.Equal(helloInfo.protocolVersion, nil, "real ACK sync must keep protocol version unresolved")
      Assert.Equal(helloInfo.capturedAt, nil, "real ACK sync must keep capture timestamp unresolved")
      Assert.Equal(helloInfo.source, "ack", "real ACK sync must mark ACK source explicitly")
    end)

    Assert.Equal(roster[1].hasIsiLive, true, "real ACK sync must mark the peer as isiLive-enabled")
    Assert.Equal(counters.uiUpdates, 1, "real ACK sync must refresh hidden UI state once")
    Assert.Equal(counters.refreshResponses, 0, "real ACK sync must not send a refresh response")
  end)
end

local function RegisterHiddenFrameBackgroundSnapshotTests(test, Assert, LoadAddonModules, Fixtures)
  test("Event handlers send sparse background snapshot on hidden zone changes", function()
    local counters = { uiUpdates = 0 }
    local backgroundSources = {}

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
      isMainFrameShown = function()
        return false
      end,
      sendOwnBackgroundSnapshot = function(source)
        table.insert(backgroundSources, source)
      end,
    })

    controller:Dispatch("ZONE_CHANGED")

    Assert.Equal(#backgroundSources, 1, "hidden zone changes must trigger one sparse background snapshot")
    Assert.Equal(backgroundSources[1], "zone", "hidden zone changes must use the zone sync source")
  end)

  test("Event handlers send sparse background snapshot only for player-owned state changes", function()
    local counters = { uiUpdates = 0 }
    local backgroundSources = {}

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
      sendOwnBackgroundSnapshot = function(source)
        table.insert(backgroundSources, source)
      end,
    })

    controller:Dispatch("PLAYER_SPECIALIZATION_CHANGED", "party1")
    controller:Dispatch("PLAYER_SPECIALIZATION_CHANGED", "player")
    controller:Dispatch("PLAYER_EQUIPMENT_CHANGED", 16, true)

    Assert.Equal(#backgroundSources, 2, "only local player state changes must trigger sparse background sync")
    Assert.Equal(backgroundSources[1], "player-state", "player specialization changes must use player-state sync")
    Assert.Equal(backgroundSources[2], "player-state", "player equipment changes must use player-state sync")
  end)
end

return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local Fixtures = ctx.fixtures

  RegisterHiddenFrameBasicSyncTests(test, Assert, LoadAddonModules, Fixtures)
  RegisterHiddenFrameRealParserKeyTests(test, Assert, LoadAddonModules, Fixtures)
  RegisterHiddenFrameRealParserStatsTests(test, Assert, LoadAddonModules, Fixtures)
  RegisterHiddenFrameRealParserDpsLocTests(test, Assert, LoadAddonModules, Fixtures)
  RegisterHiddenFrameShareKeysAndReqSyncTests(test, Assert, LoadAddonModules, Fixtures)
  RegisterHiddenFrameKickHelloAckTests(test, Assert, LoadAddonModules, Fixtures)
  RegisterHiddenFrameBackgroundSnapshotTests(test, Assert, LoadAddonModules, Fixtures)
end
