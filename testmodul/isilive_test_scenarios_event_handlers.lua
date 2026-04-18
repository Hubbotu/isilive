local function RegisterTargetHandlingTests(test, Assert, WithGlobals, LoadAddonModules, Fixtures)
  test("Event handlers keep target when active listing is inferred", function()
    local entryRef = { value = { activityID = 1001 } }
    local counters = { clears = 0, updates = 0 }

    WithGlobals({}, function()
      local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
      local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, entryRef, counters)

      controller:Dispatch("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "declined")
      Assert.Equal(counters.clears, 0, "target must stay for inferred active listing")

      entryRef.value = {}
      controller:Dispatch("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "declined")
      Assert.Equal(counters.clears, 0, "target must stay while grouped even when listing info is empty")

      entryRef.value = {}
      local pendingQueueJoinInfo = {
        groupName = "Race Group",
        priority = 2,
        capturedAt = 100,
      }
      local pendingClears = 0
      controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, entryRef, counters, {
        isInGroup = function()
          return false
        end,
        getTime = function()
          return 105
        end,
        getPendingQueueJoinInfo = function()
          return pendingQueueJoinInfo
        end,
        setPendingQueueJoinInfo = function(value)
          counters.pendingSets = counters.pendingSets + 1
          pendingQueueJoinInfo = value
          if value == nil then
            pendingClears = pendingClears + 1
          end
        end,
      })
      controller:Dispatch("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "declined")
      Assert.Equal(counters.clears, 1, "target must clear outside group when listing info is empty")
      Assert.NotNil(
        pendingQueueJoinInfo,
        "recent pending queue invite context must survive negative status race before group join"
      )
      Assert.Equal(pendingClears, 0, "recent pending queue invite context must not be cleared on negative status")

      entryRef.value = { active = false }
      pendingQueueJoinInfo = {
        groupName = "Stale Group",
        priority = 2,
        capturedAt = 70,
      }
      controller:Dispatch("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "declined")
      Assert.Equal(counters.clears, 2, "target must clear outside group for explicit inactive listing")
      Assert.Nil(pendingQueueJoinInfo, "stale pending queue invite context should clear on negative status update")
      Assert.Equal(pendingClears, 1, "stale pending queue invite context should be cleared exactly once")
    end)
  end)

  test("Event handlers keep target on negative updates when group fills to five", function()
    local counters = { clears = 0, updates = 0 }

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = {} }, counters, {
      isInGroup = function()
        return true
      end,
    })

    controller:Dispatch("LFG_LIST_APPLICATION_STATUS_UPDATED", 1, "declined")

    Assert.Equal(counters.clears, 0, "negative updates after join must not clear latest target while grouped")
    Assert.Equal(counters.updates, 1, "teleport button should still refresh on negative update")
  end)

  test("Event handlers forward positive application events to queue capture", function()
    local counters = { clears = 0, updates = 0, captures = 0 }

    WithGlobals({}, function()
      local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
      local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
        isNegativeApplicationStatusEvent = function()
          return false
        end,
      })

      controller:Dispatch("LFG_LIST_APPLICATION_STATUS_UPDATED", 7, "invited")
    end)

    Assert.Equal(counters.captures, 1, "positive application events must call queue capture")
    Assert.Equal(counters.clears, 0, "positive application events must not clear latest queue target")
  end)
end

local function RegisterTargetActiveEntryTests(test, Assert, LoadAddonModules, Fixtures)
  test("Event handlers active-entry update clears joined key and refreshes UI", function()
    local counters = { updates = 0, uiUpdates = 0, pendingSets = 0 }
    local activeJoinedKey = 2441

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(
      addon.EventHandlers,
      { value = { activityID = 1001 } },
      counters,
      {
        getActiveJoinedKeyMapID = function()
          return activeJoinedKey
        end,
        setActiveJoinedKeyMapID = function(value)
          activeJoinedKey = value
        end,
      }
    )

    controller:Dispatch("LFG_LIST_ACTIVE_ENTRY_UPDATE")

    Assert.Nil(activeJoinedKey, "active joined key map must be cleared when listing becomes active")
    Assert.Equal(counters.pendingSets, 1, "pending queue info must be cleared on active listing event")
    Assert.Equal(counters.updates, 1, "teleport button must refresh on active listing event")
    Assert.Equal(counters.uiUpdates, 1, "UI must refresh when active joined key was cleared")
  end)
end

local function RegisterGroupAndSyncTests(test, Assert, LoadAddonModules, Fixtures)
  test("Event handlers exit test mode on GROUP_ROSTER_UPDATE while grouped", function()
    local counters = { exits = 0, rosterUpdates = 0 }

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
      isTestMode = function()
        return true
      end,
    })

    controller:Dispatch("GROUP_ROSTER_UPDATE")

    Assert.Equal(counters.exits, 1, "GROUP_ROSTER_UPDATE should exit test mode when grouped")
    Assert.Equal(counters.rosterUpdates, 0, "GROUP_ROSTER_UPDATE should short-circuit after test-mode exit")
  end)

  test("Event handlers call roster update when no test mode is active", function()
    local counters = { exits = 0, rosterUpdates = 0 }

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters)

    controller:Dispatch("GROUP_ROSTER_UPDATE")

    Assert.Equal(counters.exits, 0, "normal GROUP_ROSTER_UPDATE should not exit test mode")
    Assert.Equal(counters.rosterUpdates, 1, "normal GROUP_ROSTER_UPDATE must call roster handler")
  end)

  test("Event handlers process addon sync messages and refresh changed roster", function()
    local counters = { acks = 0, uiUpdates = 0, updates = 0 }
    local statusUpdates = 0
    local kickReplies = 0
    local roster = {
      { name = "Alpha", realm = "RealmA", hasIsiLive = false },
      { name = "Beta", realm = "RealmB", hasIsiLive = true },
    }

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
      processAddonMessage = function(_prefix, _message, _sender)
        return { shouldAck = true, sender = "Alpha-RealmA" }
      end,
      forEachRosterInfo = function(visitor)
        for _, info in ipairs(roster) do
          visitor(info)
        end
      end,
      isSyncUserKnown = function(name, _realm)
        return name == "Alpha"
      end,
      applyKnownKeyToRosterEntry = function(info)
        return info.name == "Beta"
      end,
      updateStatusLine = function()
        statusUpdates = statusUpdates + 1
      end,
      sendOwnKickState = function()
        kickReplies = kickReplies + 1
      end,
    })

    controller:Dispatch("CHAT_MSG_ADDON", "ISI_SYNC", "hello", "PARTY", "Alpha-RealmA")

    Assert.Equal(counters.acks, 1, "sync payload requiring ack must send ack once")
    Assert.Equal(counters.uiUpdates, 1, "roster changes from sync must refresh UI")
    Assert.Equal(counters.updates, 1, "sync-driven target changes must refresh teleport highlight state")
    Assert.Equal(statusUpdates, 1, "sync-driven target changes must refresh statusline state")
    Assert.Equal(kickReplies, 1, "HELLO ack handling must send one kick-state reply")
    Assert.True(roster[1].hasIsiLive, "known sync user should be marked as isiLive-enabled")
  end)

  test("Event handlers refresh target-dependent UI when addon sync updates exact target only", function()
    local counters = { uiUpdates = 0, updates = 0 }
    local statusUpdates = 0

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
      processAddonMessage = function(_prefix, _message, _sender)
        return { targetUpdated = true }
      end,
      forEachRosterInfo = function(_visitor) end,
      updateStatusLine = function()
        statusUpdates = statusUpdates + 1
      end,
    })

    controller:Dispatch("CHAT_MSG_ADDON", "ISI_SYNC", "TARGET:2441:14", "PARTY", "Alpha-RealmA")

    Assert.Equal(
      counters.uiUpdates,
      1,
      "exact target sync must trigger one UI refresh even without roster field changes"
    )
    Assert.Equal(counters.updates, 1, "exact target sync must refresh teleport highlight state")
    Assert.Equal(statusUpdates, 1, "exact target sync must refresh statusline state")
  end)
end

local function RegisterChallengeRaidResumeTests(test, Assert, LoadAddonModules, Fixtures)
  test("Event handlers defer post-run refresh while raid mode is active and resume after raid exit", function()
    local delayedCallback = nil
    local raidActive = false
    local refreshCalls = 0
    local enableCalls = 0
    local rosterUpdates = 0

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, {}, {
      timerAfter = function(seconds, callback)
        if seconds == 5 then
          delayedCallback = callback
        end
      end,
      isRaidGroup = function()
        return raidActive
      end,
      handleGroupRosterUpdate = function()
        rosterUpdates = rosterUpdates + 1
      end,
      runFullRefresh = function()
        refreshCalls = refreshCalls + 1
        return true
      end,
      enableRioDeltaDisplay = function()
        enableCalls = enableCalls + 1
      end,
    })

    controller:Dispatch("CHALLENGE_MODE_COMPLETED")

    Assert.NotNil(delayedCallback, "challenge completion must still schedule a delayed post-run refresh")
    if type(delayedCallback) ~= "function" then
      return
    end

    raidActive = true
    delayedCallback()

    Assert.Equal(refreshCalls, 0, "delayed post-run refresh must not run while raid mode is active")
    Assert.Equal(enableCalls, 0, "RIO delta must stay disabled while the delayed refresh is deferred in raid")

    controller:Dispatch("GROUP_ROSTER_UPDATE")

    Assert.Equal(rosterUpdates, 1, "raid mode must still route roster updates while refresh is deferred")
    Assert.Equal(refreshCalls, 0, "raid roster updates must not resume the deferred post-run refresh yet")
    Assert.Equal(enableCalls, 0, "raid roster updates must not enable RIO delta yet")

    raidActive = false
    controller:Dispatch("GROUP_ROSTER_UPDATE")

    Assert.Equal(rosterUpdates, 2, "raid exit detection must still flow through GROUP_ROSTER_UPDATE")
    Assert.Equal(refreshCalls, 1, "first roster update after raid exit must resume the deferred post-run refresh")
    Assert.Equal(enableCalls, 1, "RIO delta must enable after the resumed post-run refresh succeeds")
  end)
end

return function(test, ctx)
  local Assert = ctx.assert
  local WithGlobals = ctx.with_globals
  local LoadAddonModules = ctx.load_modules
  local Fixtures = ctx.fixtures

  RegisterTargetHandlingTests(test, Assert, WithGlobals, LoadAddonModules, Fixtures)
  RegisterTargetActiveEntryTests(test, Assert, LoadAddonModules, Fixtures)
  RegisterGroupAndSyncTests(test, Assert, LoadAddonModules, Fixtures)
  RegisterChallengeRaidResumeTests(test, Assert, LoadAddonModules, Fixtures)
end
