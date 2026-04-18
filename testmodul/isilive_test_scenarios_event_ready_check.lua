local function RegisterReadyCheckHoldAndRunRecordTests(test, Assert, WithGlobals, LoadAddonModules, Fixtures)
  test("Event handlers keep unanswered ready-check rows red for 20 seconds after finish", function()
    local counters = { uiUpdates = 0, readyCheckRefreshes = 0 }
    local readyCheckActive = false
    local now = 100
    local readyUntilByUnit = {}
    local declinedUntilByUnit = {}
    local scheduledDelay = nil
    local scheduledCallback = nil

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
      setReadyCheckActive = function(value)
        readyCheckActive = value and true or false
      end,
      isReadyCheckActive = function()
        return readyCheckActive
      end,
      getTime = function()
        return now
      end,
      getRoster = function()
        return {
          party1 = { name = "ReadyMate", role = "DAMAGER" },
          party2 = { name = "SilentMate", role = "DAMAGER" },
        }
      end,
      setReadyCheckReadyUntil = function(unit, value)
        readyUntilByUnit[unit] = value
      end,
      clearAllReadyCheckReady = function()
        readyUntilByUnit = {}
      end,
      clearExpiredReadyCheckReady = function(currentTime)
        local changed = false
        for unit, untilTime in pairs(readyUntilByUnit) do
          if untilTime <= currentTime then
            readyUntilByUnit[unit] = nil
            changed = true
          end
        end
        return changed
      end,
      setReadyCheckDeclinedUntil = function(unit, value)
        declinedUntilByUnit[unit] = value
      end,
      clearAllReadyCheckDeclined = function()
        declinedUntilByUnit = {}
      end,
      clearExpiredReadyCheckDeclined = function(currentTime)
        local changed = false
        for unit, untilTime in pairs(declinedUntilByUnit) do
          if untilTime <= currentTime then
            declinedUntilByUnit[unit] = nil
            changed = true
          end
        end
        return changed
      end,
      timerAfter = function(delaySeconds, callback)
        scheduledDelay = delaySeconds
        scheduledCallback = callback
      end,
    })

    controller:Dispatch("READY_CHECK")
    controller:Dispatch("READY_CHECK_CONFIRM", "party1", "ready")
    controller:Dispatch("READY_CHECK_FINISHED")

    Assert.False(readyCheckActive, "READY_CHECK_FINISHED must clear ready check state")
    Assert.Equal(readyUntilByUnit.party1, 120, "explicit ready answers should stay green for 20 seconds")
    Assert.Equal(declinedUntilByUnit.party2, 120, "missing ready-check answers should stay red for 20 seconds")
    Assert.Nil(declinedUntilByUnit.party1, "ready answers must not also receive a declined hold")
    Assert.Equal(scheduledDelay, 20, "unanswered ready-check hold should schedule one 20-second cleanup refresh")
    Assert.NotNil(scheduledCallback, "unanswered ready-check hold must schedule a cleanup callback")
    Assert.Equal(counters.readyCheckRefreshes, 3, "finish path should still refresh the dedicated ready-check UI")
    Assert.Equal(counters.uiUpdates, 0, "unanswered ready-check hold must not use generic updateUI")

    now = 120
    local cleanupCallback = scheduledCallback
    if cleanupCallback == nil then
      error("unanswered ready-check hold must schedule a cleanup callback")
    end
    cleanupCallback()

    Assert.Nil(readyUntilByUnit.party1, "ready hold should clear after the timer expires")
    Assert.Nil(declinedUntilByUnit.party2, "unanswered declined hold should clear after the timer expires")
    Assert.Equal(counters.readyCheckRefreshes, 4, "timer expiry should trigger one more dedicated ready-check refresh")
    Assert.Equal(counters.uiUpdates, 0, "timer expiry must not use generic updateUI")
  end)

  test("Event handlers record completed run only once across completion and reset events", function()
    local recordedRuns = {}

    WithGlobals({
      C_ChallengeMode = {
        GetCompletionInfo = function()
          return 2662, 10, 123456, true
        end,
      },
    }, function()
      local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
      local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, {}, {
        recordRun = function(mapID, level, onTime)
          table.insert(recordedRuns, {
            mapID = mapID,
            level = level,
            onTime = onTime,
          })
        end,
      })

      controller:Dispatch("CHALLENGE_MODE_COMPLETED")
      controller:Dispatch("CHALLENGE_MODE_RESET")
      Assert.Equal(#recordedRuns, 1, "completion/reset pair must record the run only once")

      controller:Dispatch("CHALLENGE_MODE_START")
      controller:Dispatch("CHALLENGE_MODE_COMPLETED")
      Assert.Equal(#recordedRuns, 2, "new run after challenge start should be recordable again")
    end)
  end)
end

local function RegisterReadyCheckLifecycleTests(test, Assert, _WithGlobals, LoadAddonModules, Fixtures)
  test("Event handlers toggle ready check state and refresh UI on ready check events", function()
    local counters = { uiUpdates = 0, readyCheckRefreshes = 0 }
    local readyCheckActive = false
    local now = 100
    local readyUntilByUnit = {}
    local scheduledDelay = nil
    local scheduledCallback = nil

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
      setReadyCheckActive = function(value)
        readyCheckActive = value and true or false
      end,
      isReadyCheckActive = function()
        return readyCheckActive
      end,
      getTime = function()
        return now
      end,
      setReadyCheckReadyUntil = function(unit, value)
        readyUntilByUnit[unit] = value
      end,
      clearAllReadyCheckReady = function()
        readyUntilByUnit = {}
      end,
      clearExpiredReadyCheckReady = function(currentTime)
        local changed = false
        for unit, untilTime in pairs(readyUntilByUnit) do
          if untilTime <= currentTime then
            readyUntilByUnit[unit] = nil
            changed = true
          end
        end
        return changed
      end,
      timerAfter = function(delaySeconds, callback)
        scheduledDelay = delaySeconds
        scheduledCallback = callback
      end,
    })

    controller:Dispatch("READY_CHECK")
    Assert.True(readyCheckActive, "READY_CHECK must mark ready check as active")
    Assert.Equal(counters.readyCheckRefreshes, 1, "READY_CHECK should refresh ready-check UI once")
    Assert.Equal(counters.uiUpdates, 0, "READY_CHECK must not call the generic UI rerender path")

    controller:Dispatch("READY_CHECK_CONFIRM", "party1", "ready")
    Assert.Equal(
      counters.readyCheckRefreshes,
      2,
      "READY_CHECK_CONFIRM should refresh the dedicated ready-check UI while active"
    )
    Assert.Equal(counters.uiUpdates, 0, "READY_CHECK_CONFIRM must not call the generic UI rerender path")

    controller:Dispatch("READY_CHECK_FINISHED")
    Assert.False(readyCheckActive, "READY_CHECK_FINISHED must clear ready check state")
    Assert.Equal(counters.readyCheckRefreshes, 3, "READY_CHECK_FINISHED should refresh ready-check UI once")
    Assert.Equal(counters.uiUpdates, 0, "READY_CHECK_FINISHED must not call the generic UI rerender path")
    Assert.Equal(readyUntilByUnit.party1, 120, "READY_CHECK_FINISHED should keep ready unit green for 20 seconds")
    Assert.Equal(scheduledDelay, 20, "READY_CHECK_FINISHED should schedule a 20-second ready hold cleanup")
    Assert.NotNil(scheduledCallback, "READY_CHECK_FINISHED should schedule a ready-hold cleanup callback")

    now = 121
    controller:Dispatch("READY_CHECK_CONFIRM", "party1", "ready")
    Assert.Equal(
      counters.readyCheckRefreshes,
      4,
      "READY_CHECK_CONFIRM should still refresh ready-check UI after ready check finished"
    )
    Assert.Equal(counters.uiUpdates, 0, "READY_CHECK_CONFIRM after finish must keep the generic UI rerender path idle")
    Assert.Equal(readyUntilByUnit.party1, 141, "late ready confirm should refresh its 20-second hold")
    Assert.Equal(scheduledDelay, 20, "late ready confirm should schedule a 20-second cleanup")
    Assert.NotNil(scheduledCallback, "late ready confirm should schedule a cleanup callback")

    now = 141
    local cleanupCallback = scheduledCallback
    if cleanupCallback == nil then
      error("late ready confirm should schedule a cleanup callback")
    end
    cleanupCallback()

    Assert.Nil(readyUntilByUnit.party1, "late ready confirm hold should clear after the timer expires")
    Assert.Equal(counters.readyCheckRefreshes, 5, "ready-hold expiry should trigger one more ready-check refresh")
    Assert.Equal(counters.uiUpdates, 0, "ready-hold expiry must not call the generic UI rerender path")
  end)

  test("Event handlers write ready check trace entries when runtime logging is available", function()
    local counters = { uiUpdates = 0, readyCheckRefreshes = 0 }
    local readyCheckActive = false
    local now = 100
    local readyUntilByUnit = {}
    local declinedUntilByUnit = {}
    local scheduledCallback = nil
    local logEntries = {}

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
      setReadyCheckActive = function(value)
        readyCheckActive = value and true or false
      end,
      isReadyCheckActive = function()
        return readyCheckActive
      end,
      getTime = function()
        return now
      end,
      getRoster = function()
        return {
          party1 = { name = "ReadyOne" },
          party2 = { name = "ReadyTwo" },
        }
      end,
      setReadyCheckReadyUntil = function(unit, value)
        readyUntilByUnit[unit] = value
      end,
      getReadyCheckReadyUntil = function(unit)
        return readyUntilByUnit[unit]
      end,
      clearAllReadyCheckReady = function()
        readyUntilByUnit = {}
      end,
      setReadyCheckDeclinedUntil = function(unit, value)
        declinedUntilByUnit[unit] = value
      end,
      getReadyCheckDeclinedUntil = function(unit)
        return declinedUntilByUnit[unit]
      end,
      clearAllReadyCheckDeclined = function()
        declinedUntilByUnit = {}
      end,
      clearExpiredReadyCheckReady = function(currentTime)
        local changed = false
        for unit, untilTime in pairs(readyUntilByUnit) do
          if untilTime <= currentTime then
            readyUntilByUnit[unit] = nil
            changed = true
          end
        end
        return changed
      end,
      clearExpiredReadyCheckDeclined = function(currentTime)
        local changed = false
        for unit, untilTime in pairs(declinedUntilByUnit) do
          if untilTime <= currentTime then
            declinedUntilByUnit[unit] = nil
            changed = true
          end
        end
        return changed
      end,
      timerAfter = function(_delaySeconds, callback)
        scheduledCallback = callback
      end,
      logRuntimeTrace = function(message)
        table.insert(logEntries, message)
      end,
      logRuntimeTracef = function(fmt, ...)
        table.insert(logEntries, string.format(fmt, ...))
      end,
    })

    controller:Dispatch("READY_CHECK")
    controller:Dispatch("READY_CHECK_CONFIRM", "party1", "ready")
    controller:Dispatch("READY_CHECK_FINISHED")

    Assert.Equal(#logEntries, 7, "ready check lifecycle should emit seven trace entries before cleanup")
    Assert.True(
      logEntries[1]:find("[EVENT_DISPATCH] event=READY_CHECK handled=true", 1, true) ~= nil,
      "first trace entry must record the READY_CHECK dispatch"
    )
    Assert.True(logEntries[2]:find("event=READY_CHECK", 1, true) ~= nil, "second trace entry must record READY_CHECK")
    Assert.True(
      logEntries[3]:find("[EVENT_DISPATCH] event=READY_CHECK_CONFIRM handled=true", 1, true) ~= nil,
      "third trace entry must record the READY_CHECK_CONFIRM dispatch"
    )
    Assert.True(
      logEntries[4]:find("event=READY_CHECK_CONFIRM", 1, true) ~= nil,
      "fourth trace entry must record READY_CHECK_CONFIRM"
    )
    Assert.True(
      logEntries[5]:find("[EVENT_DISPATCH] event=READY_CHECK_FINISHED handled=true", 1, true) ~= nil,
      "fifth trace entry must record the READY_CHECK_FINISHED dispatch"
    )
    Assert.True(
      logEntries[6]:find("event=READY_CHECK_FINISHED", 1, true) ~= nil,
      "sixth trace entry must record READY_CHECK_FINISHED"
    )
    Assert.True(
      logEntries[7]:find("[RC_FINISH_HOLD]", 1, true) ~= nil,
      "seventh trace entry must record the ready-check hold snapshot"
    )
    Assert.True(
      logEntries[7]:find("ready_units=party1", 1, true) ~= nil,
      "hold snapshot must record the explicitly ready unit"
    )
    Assert.True(
      logEntries[7]:find("declined_units=party2", 1, true) ~= nil,
      "hold snapshot must record unanswered units promoted to declined"
    )
    Assert.True(
      logEntries[7]:find("ready_until_count=1", 1, true) ~= nil,
      "hold snapshot must count ready hold entries"
    )
    Assert.True(
      logEntries[7]:find("declined_until_count=1", 1, true) ~= nil,
      "hold snapshot must count declined hold entries"
    )

    now = 120
    local cleanupCallback = scheduledCallback
    if cleanupCallback == nil then
      error("ready check trace test must schedule a cleanup callback")
    end
    cleanupCallback()

    Assert.Equal(#logEntries, 8, "cleanup callback should append a hold-clear trace entry")
    Assert.True(logEntries[8]:find("event=HOLD_CLEAR", 1, true) ~= nil, "cleanup trace must record HOLD_CLEAR")
  end)
end

local function RegisterReadyCheckHoldTests(test, Assert, _WithGlobals, LoadAddonModules, Fixtures)
  test("Event handlers keep declined ready-check rows red for 20 seconds after finish", function()
    local counters = { uiUpdates = 0, readyCheckRefreshes = 0 }
    local readyCheckActive = false
    local now = 100
    local declinedUntilByUnit = {}
    local scheduledDelay = nil
    local scheduledCallback = nil

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
      setReadyCheckActive = function(value)
        readyCheckActive = value and true or false
      end,
      isReadyCheckActive = function()
        return readyCheckActive
      end,
      getTime = function()
        return now
      end,
      setReadyCheckDeclinedUntil = function(unit, value)
        declinedUntilByUnit[unit] = value
      end,
      clearAllReadyCheckDeclined = function()
        declinedUntilByUnit = {}
      end,
      clearExpiredReadyCheckDeclined = function(currentTime)
        local changed = false
        for unit, untilTime in pairs(declinedUntilByUnit) do
          if untilTime <= currentTime then
            declinedUntilByUnit[unit] = nil
            changed = true
          end
        end
        return changed
      end,
      timerAfter = function(delaySeconds, callback)
        scheduledDelay = delaySeconds
        scheduledCallback = callback
      end,
    })

    controller:Dispatch("READY_CHECK")
    controller:Dispatch("READY_CHECK_CONFIRM", "party1", "notready")
    controller:Dispatch("READY_CHECK_CONFIRM", "party2", "ready")
    controller:Dispatch("READY_CHECK_FINISHED")

    Assert.False(readyCheckActive, "READY_CHECK_FINISHED must clear ready check state")
    Assert.Equal(declinedUntilByUnit.party1, 120, "declined ready-check unit should stay marked for 20 seconds")
    Assert.Nil(declinedUntilByUnit.party2, "ready unit must not receive a declined hold")
    Assert.Equal(scheduledDelay, 20, "declined ready-check hold should schedule one 20-second cleanup refresh")
    Assert.NotNil(scheduledCallback, "declined ready-check hold must schedule a cleanup callback")
    Assert.Equal(counters.readyCheckRefreshes, 4, "finish path should still refresh the dedicated ready-check UI")
    Assert.Equal(counters.uiUpdates, 0, "declined ready-check hold must not use generic updateUI")

    now = 120
    local cleanupCallback = scheduledCallback
    if cleanupCallback == nil then
      error("declined ready-check hold must schedule a cleanup callback")
    end
    cleanupCallback()

    Assert.Nil(declinedUntilByUnit.party1, "declined ready-check hold should clear after the timer expires")
    Assert.Equal(counters.readyCheckRefreshes, 5, "timer expiry should trigger one more dedicated ready-check refresh")
    Assert.Equal(counters.uiUpdates, 0, "timer expiry must not use generic updateUI")
  end)

  test("Event handlers keep ready-check rows green for 20 seconds after finish", function()
    local counters = { uiUpdates = 0, readyCheckRefreshes = 0 }
    local readyCheckActive = false
    local now = 100
    local readyUntilByUnit = {}
    local scheduledDelay = nil
    local scheduledCallback = nil

    local addon = LoadAddonModules({ "isiLive_event_handlers.lua" })
    local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, counters, {
      setReadyCheckActive = function(value)
        readyCheckActive = value and true or false
      end,
      isReadyCheckActive = function()
        return readyCheckActive
      end,
      getTime = function()
        return now
      end,
      setReadyCheckReadyUntil = function(unit, value)
        readyUntilByUnit[unit] = value
      end,
      clearAllReadyCheckReady = function()
        readyUntilByUnit = {}
      end,
      clearExpiredReadyCheckReady = function(currentTime)
        local changed = false
        for unit, untilTime in pairs(readyUntilByUnit) do
          if untilTime <= currentTime then
            readyUntilByUnit[unit] = nil
            changed = true
          end
        end
        return changed
      end,
      timerAfter = function(delaySeconds, callback)
        scheduledDelay = delaySeconds
        scheduledCallback = callback
      end,
    })

    controller:Dispatch("READY_CHECK")
    controller:Dispatch("READY_CHECK_CONFIRM", "party2", "ready")
    controller:Dispatch("READY_CHECK_FINISHED")

    Assert.False(readyCheckActive, "READY_CHECK_FINISHED must clear ready check state")
    Assert.Equal(readyUntilByUnit.party2, 120, "ready ready-check unit should stay marked for 20 seconds")
    Assert.Equal(scheduledDelay, 20, "ready ready-check hold should schedule one 20-second cleanup refresh")
    Assert.NotNil(scheduledCallback, "ready ready-check hold must schedule a cleanup callback")
    Assert.Equal(counters.readyCheckRefreshes, 3, "finish path should still refresh the dedicated ready-check UI")
    Assert.Equal(counters.uiUpdates, 0, "ready ready-check hold must not use generic updateUI")

    now = 120
    local cleanupCallback = scheduledCallback
    if cleanupCallback == nil then
      error("ready ready-check hold must schedule a cleanup callback")
    end
    cleanupCallback()

    Assert.Nil(readyUntilByUnit.party2, "ready ready-check hold should clear after the timer expires")
    Assert.Equal(counters.readyCheckRefreshes, 4, "timer expiry should trigger one more dedicated ready-check refresh")
    Assert.Equal(counters.uiUpdates, 0, "timer expiry must not use generic updateUI")
  end)
end

local function RegisterReadyCheckAndStatsTests(test, Assert, WithGlobals, LoadAddonModules, Fixtures)
  RegisterReadyCheckLifecycleTests(test, Assert, WithGlobals, LoadAddonModules, Fixtures)
  RegisterReadyCheckHoldTests(test, Assert, WithGlobals, LoadAddonModules, Fixtures)
  RegisterReadyCheckHoldAndRunRecordTests(test, Assert, WithGlobals, LoadAddonModules, Fixtures)
end

return function(test, ctx)
  local Assert = ctx.assert
  local WithGlobals = ctx.with_globals
  local LoadAddonModules = ctx.load_modules
  local Fixtures = ctx.fixtures

  RegisterReadyCheckAndStatsTests(test, Assert, WithGlobals, LoadAddonModules, Fixtures)
end
