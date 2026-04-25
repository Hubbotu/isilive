---@diagnostic disable: undefined-global

local function BuildScenarioStubs(overrides)
  overrides = overrides or {}
  local criterionQuantity = overrides.quantity or 0
  local totalQuantity = overrides.total or 100
  local activeMapID = overrides.mapID or 556

  local C_ChallengeMode_stub = {
    GetActiveChallengeMapID = function()
      return activeMapID
    end,
  }

  local C_ScenarioInfo_stub = {
    GetScenarioStepInfo = function()
      return { numCriteria = 1 }
    end,
    GetCriteriaInfo = function(_i)
      return {
        isWeightedProgress = true,
        totalQuantity = totalQuantity,
        quantityString = tostring(criterionQuantity),
        quantity = criterionQuantity,
      }
    end,
  }

  local handle = {
    SetQuantity = function(q)
      criterionQuantity = q
    end,
    SetTotal = function(t)
      totalQuantity = t
    end,
    SetActiveMapID = function(id)
      activeMapID = id
    end,
    GetQuantity = function()
      return criterionQuantity
    end,
  }

  return C_ChallengeMode_stub, C_ScenarioInfo_stub, handle
end

local function BuildTimerStub()
  local scheduled = {}
  local tickers = {}
  local stub = {
    After = function(delay, fn)
      table.insert(scheduled, { delay = delay, fn = fn })
    end,
    NewTicker = function(interval, fn)
      local ticker = {
        interval = interval,
        fn = fn,
        cancelled = false,
      }
      ticker.Cancel = function(self)
        self.cancelled = true
      end
      table.insert(tickers, ticker)
      return ticker
    end,
  }
  return stub, scheduled, tickers
end

local function BuildFrameStub()
  local registered = {}
  local handler = nil
  local frame = {
    RegisterEvent = function(_self, event)
      registered[event] = true
    end,
    UnregisterEvent = function(_self, event)
      registered[event] = nil
    end,
    SetScript = function(_self, scriptType, fn)
      if scriptType == "OnEvent" then
        handler = fn
      end
    end,
  }
  return frame, registered, function()
    return handler
  end
end

local function BuildKillTrackEnv(overrides)
  overrides = overrides or {}
  local C_ChallengeMode_stub, C_ScenarioInfo_stub, scenario = BuildScenarioStubs(overrides.scenario)
  local timerStub, scheduled, tickers = BuildTimerStub()
  local frame, registered, getHandler = BuildFrameStub()
  local clock = { now = overrides.nowStart or 1000 }

  local globals = {
    CreateFrame = function(_type)
      return frame
    end,
    C_ChallengeMode = C_ChallengeMode_stub,
    C_ScenarioInfo = C_ScenarioInfo_stub,
    C_Timer = timerStub,
    GetTime = function()
      return clock.now
    end,
  }
  if overrides.globals then
    for k, v in pairs(overrides.globals) do
      globals[k] = v
    end
  end

  return {
    globals = globals,
    scenario = scenario,
    scheduled = scheduled,
    tickers = tickers,
    registered = registered,
    frame = frame,
    clock = clock,
    getHandler = getHandler,
  }
end

local function RegisterEventRegistrationTests(test, Assert, WithGlobals, LoadAddonModules)
  test("KillTrack registers the expected challenge-mode and combat events", function()
    local env = BuildKillTrackEnv()
    WithGlobals(env.globals, function()
      LoadAddonModules({ "isiLive_killtrack.lua" })
    end)
    Assert.True(env.registered["CHALLENGE_MODE_START"], "must register CHALLENGE_MODE_START")
    Assert.True(env.registered["CHALLENGE_MODE_COMPLETED"], "must register CHALLENGE_MODE_COMPLETED")
    Assert.True(env.registered["CHALLENGE_MODE_RESET"], "must register CHALLENGE_MODE_RESET")
    Assert.True(env.registered["SCENARIO_CRITERIA_UPDATE"], "must register SCENARIO_CRITERIA_UPDATE")
    Assert.True(env.registered["PLAYER_REGEN_DISABLED"], "must register PLAYER_REGEN_DISABLED")
    Assert.True(env.registered["PLAYER_REGEN_ENABLED"], "must register PLAYER_REGEN_ENABLED")
  end)
end

local function RegisterStateTests(test, Assert, WithGlobals, LoadAddonModules)
  test("KillTrack reports active state and percent when a key is running", function()
    local env = BuildKillTrackEnv({ scenario = { quantity = 25, total = 100 } })
    WithGlobals(env.globals, function()
      local addon = LoadAddonModules({ "isiLive_killtrack.lua" })
      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_START")
      local data = addon.KillTrack.GetData()
      Assert.True(data.active, "KillTrack must report active during a key")
      Assert.Equal(data.rawCount, 25, "rawCount must come from the scenario criterion")
      Assert.Equal(data.total, 100, "total must come from the scenario criterion")
      Assert.True(math.abs(data.percent - 25) < 0.01, "percent must be rawCount / total * 100")
    end)
  end)

  test("KillTrack resets all state on CHALLENGE_MODE_COMPLETED", function()
    local env = BuildKillTrackEnv({ scenario = { quantity = 60, total = 100 } })
    WithGlobals(env.globals, function()
      local addon = LoadAddonModules({ "isiLive_killtrack.lua" })
      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_START")
      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_COMPLETED")
      local data = addon.KillTrack.GetData()
      Assert.False(data.active, "KillTrack must reset active on completion")
      Assert.Equal(data.rawCount, 0, "rawCount must reset to zero")
      Assert.Equal(data.percent, 0, "percent must reset to zero")
      Assert.Equal(data.pullPercent, 0, "pullPercent must reset to zero")
    end)
  end)

  test("KillTrack GetData returns inactive when no challenge map is active", function()
    local env = BuildKillTrackEnv()
    env.globals.C_ChallengeMode = {
      GetActiveChallengeMapID = function()
        return nil
      end,
    }
    WithGlobals(env.globals, function()
      local addon = LoadAddonModules({ "isiLive_killtrack.lua" })
      addon.KillTrack._DispatchEvent("PLAYER_ENTERING_WORLD")
      local data = addon.KillTrack.GetData()
      Assert.False(data.active, "no active challenge map must mark KillTrack inactive")
    end)
  end)
end

local function RegisterPullBaselineTests(test, Assert, WithGlobals, LoadAddonModules)
  test("PLAYER_REGEN_DISABLED refreshes live data before capturing the pull baseline", function()
    local env = BuildKillTrackEnv({ scenario = { quantity = 10, total = 100 } })
    WithGlobals(env.globals, function()
      local addon = LoadAddonModules({ "isiLive_killtrack.lua" })
      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_START")
      -- Quantity changes while out-of-combat; next SCENARIO_CRITERIA_UPDATE
      -- hasn't fired yet when combat starts.
      env.scenario.SetQuantity(30)
      addon.KillTrack._DispatchEvent("PLAYER_REGEN_DISABLED")
      -- First kill: quantity reaches 35 → delta must be 5, not 25.
      env.scenario.SetQuantity(35)
      addon.KillTrack._DispatchEvent("SCENARIO_CRITERIA_UPDATE")
      local data = addon.KillTrack.GetData()
      Assert.True(data.inCombat, "pull must be active in combat")
      Assert.True(math.abs(data.pullPercent - 5) < 0.01, "pullPercent must reflect kills since baseline")
    end)
  end)

  test("pullPercent remains visible during the post-combat grace window", function()
    local env = BuildKillTrackEnv({ scenario = { quantity = 10, total = 100 }, nowStart = 1000 })
    WithGlobals(env.globals, function()
      local addon = LoadAddonModules({ "isiLive_killtrack.lua" })
      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_START")
      addon.KillTrack._DispatchEvent("PLAYER_REGEN_DISABLED")
      env.scenario.SetQuantity(18)
      addon.KillTrack._DispatchEvent("SCENARIO_CRITERIA_UPDATE")
      Assert.True(addon.KillTrack.GetData().inCombat, "inCombat should remain true during the pull")

      addon.KillTrack._DispatchEvent("PLAYER_REGEN_ENABLED")
      -- Clock advances within the grace window.
      env.clock.now = 1001
      local data = addon.KillTrack.GetData()
      Assert.True(data.inCombat, "pull display must persist within the grace window")
      Assert.True(data.pullPercent > 0, "pullPercent must remain > 0 within the grace window")

      -- Clock advances past the grace window.
      env.clock.now = 1005
      data = addon.KillTrack.GetData()
      Assert.False(data.inCombat, "pull display must expire after the grace window")
      Assert.Equal(data.pullPercent, 0, "pullPercent must be cleared after the grace window")
    end)
  end)

  test("PLAYER_REGEN_DISABLED does not start a pull when no key is active", function()
    local env = BuildKillTrackEnv({
      scenario = { quantity = 10, total = 100 },
    })
    env.globals.C_ChallengeMode = {
      GetActiveChallengeMapID = function()
        return nil
      end,
    }
    WithGlobals(env.globals, function()
      local addon = LoadAddonModules({ "isiLive_killtrack.lua" })
      addon.KillTrack._DispatchEvent("PLAYER_REGEN_DISABLED")
      local data = addon.KillTrack.GetData()
      Assert.False(data.active, "no key active must keep KillTrack inactive")
      Assert.False(data.inCombat, "no key active must not mark pull in combat")
    end)
  end)
end

local function RegisterSubscriberTests(test, Assert, WithGlobals, LoadAddonModules)
  test("KillTrack.OnUpdate fires on scenario, combat, and challenge events", function()
    local env = BuildKillTrackEnv({ scenario = { quantity = 5, total = 100 } })
    WithGlobals(env.globals, function()
      local addon = LoadAddonModules({ "isiLive_killtrack.lua" })
      local calls = 0
      addon.KillTrack.OnUpdate(function()
        calls = calls + 1
      end)
      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_START")
      local afterStart = calls
      addon.KillTrack._DispatchEvent("PLAYER_REGEN_DISABLED")
      local afterCombat = calls
      addon.KillTrack._DispatchEvent("SCENARIO_CRITERIA_UPDATE")
      local afterCriteria = calls
      addon.KillTrack._DispatchEvent("PLAYER_REGEN_ENABLED")
      local afterRegenEnabled = calls
      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_COMPLETED")
      local afterComplete = calls

      Assert.True(afterStart > 0, "subscriber must be notified on CHALLENGE_MODE_START")
      Assert.True(afterCombat > afterStart, "subscriber must be notified on PLAYER_REGEN_DISABLED")
      Assert.True(afterCriteria > afterCombat, "subscriber must be notified on SCENARIO_CRITERIA_UPDATE")
      Assert.True(afterRegenEnabled > afterCriteria, "subscriber must be notified on PLAYER_REGEN_ENABLED")
      Assert.True(afterComplete > afterRegenEnabled, "subscriber must be notified on CHALLENGE_MODE_COMPLETED")
    end)
  end)

  test("KillTrack.OnUpdate rejects duplicate registrations of the same callback", function()
    local env = BuildKillTrackEnv({ scenario = { quantity = 5, total = 100 } })
    WithGlobals(env.globals, function()
      local addon = LoadAddonModules({ "isiLive_killtrack.lua" })
      local calls = 0
      local cb = function()
        calls = calls + 1
      end
      addon.KillTrack.OnUpdate(cb)
      addon.KillTrack.OnUpdate(cb)
      addon.KillTrack.OnUpdate(cb)
      addon.KillTrack._DispatchEvent("SCENARIO_CRITERIA_UPDATE")
      Assert.Equal(calls, 1, "duplicate registrations of the same callback must collapse")
    end)
  end)
end

local function RegisterTickerTests(test, Assert, WithGlobals, LoadAddonModules)
  test("KillTrack starts a refresh ticker while the key is active and stops it afterwards", function()
    local env = BuildKillTrackEnv({ scenario = { quantity = 5, total = 100 } })
    WithGlobals(env.globals, function()
      local addon = LoadAddonModules({ "isiLive_killtrack.lua" })
      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_START")
      Assert.Equal(#env.tickers, 1, "a refresh ticker must be created when the key starts")
      Assert.False(env.tickers[1].cancelled, "the refresh ticker must not be cancelled while the key is active")

      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_COMPLETED")
      Assert.True(env.tickers[1].cancelled, "the refresh ticker must be cancelled when the key ends")
    end)
  end)

  test("refresh ticker callback notifies subscribers while state is active", function()
    local env = BuildKillTrackEnv({ scenario = { quantity = 5, total = 100 } })
    WithGlobals(env.globals, function()
      local addon = LoadAddonModules({ "isiLive_killtrack.lua" })
      local calls = 0
      addon.KillTrack.OnUpdate(function()
        calls = calls + 1
      end)
      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_START")
      local before = calls
      -- Simulate the ticker firing.
      env.tickers[1].fn()
      Assert.True(calls > before, "ticker firing must notify subscribers while state is active")
    end)
  end)
end

local function RegisterDbTotalAndMapIdTests(test, Assert, WithGlobals, LoadAddonModules)
  test("KillTrack.GetData exposes the active challenge mapID for downstream consumers", function()
    local env = BuildKillTrackEnv({ scenario = { quantity = 25, total = 100, mapID = 559 } })
    WithGlobals(env.globals, function()
      local addon = LoadAddonModules({ "isiLive_killtrack.lua" })
      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_START")
      local data = addon.KillTrack.GetData()
      Assert.Equal(data.mapID, 559, "GetData must surface the active challenge mapID for UI lookups")
    end)
  end)

  test("KillTrack.GetData clears mapID on CHALLENGE_MODE_COMPLETED", function()
    local env = BuildKillTrackEnv({ scenario = { quantity = 25, total = 100, mapID = 559 } })
    WithGlobals(env.globals, function()
      local addon = LoadAddonModules({ "isiLive_killtrack.lua" })
      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_START")
      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_COMPLETED")
      local data = addon.KillTrack.GetData()
      Assert.Equal(data.mapID, nil, "mapID must reset to nil when the key ends")
    end)
  end)

  test("KillTrack falls back to MPlusForces.dungeonTotal when API totalQuantity is missing", function()
    local env = BuildKillTrackEnv({ scenario = { quantity = 25, total = 100, mapID = 559 } })
    -- Simulate Blizzard API returning a nil totalQuantity (e.g. tainted in a
    -- protected context). API has primacy normally; with API absent, the DB
    -- value drives the percent calculation.
    env.globals.C_ScenarioInfo.GetCriteriaInfo = function()
      return {
        isWeightedProgress = true,
        totalQuantity = nil,
        quantityString = "25",
        quantity = 25,
      }
    end
    WithGlobals(env.globals, function()
      local addon = LoadAddonModules({ "isiLive_killtrack.lua" }, {
        MPlusForces = {
          dungeonTotal = { [559] = { total = 596, name = "Nexus Point Xenas" } },
          byNpcId = {},
        },
      })
      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_START")
      local data = addon.KillTrack.GetData()
      Assert.Equal(data.total, 596, "total must come from MPlusForces.dungeonTotal when API total is missing")
      Assert.True(math.abs(data.percent - (25 / 596) * 100) < 0.01, "percent uses DB-total when API-total is absent")
    end)
  end)

  test("KillTrack ignores DB total when API total is present and uses API-total instead", function()
    -- API-total has primacy because rawCount also comes from the API; mixing
    -- API-rawCount with DB-total would produce off-by-fraction percentages
    -- after a Blizzard-side patch shifts the dungeon's max forces value.
    local env = BuildKillTrackEnv({ scenario = { quantity = 50, total = 450, mapID = 559 } })
    WithGlobals(env.globals, function()
      local addon = LoadAddonModules({ "isiLive_killtrack.lua" }, {
        MPlusForces = {
          dungeonTotal = { [559] = { total = 596, name = "Nexus Point Xenas" } },
          byNpcId = {},
        },
      })
      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_START")
      local data = addon.KillTrack.GetData()
      Assert.Equal(data.total, 450, "API total must win when present, even if DB has a different value")
    end)
  end)

  test("KillTrack debug logger fires once on API/DB total drift, then suppresses repeats", function()
    local env = BuildKillTrackEnv({ scenario = { quantity = 50, total = 450, mapID = 559 } })
    local driftMessages = {}
    WithGlobals(env.globals, function()
      local addon = LoadAddonModules({ "isiLive_killtrack.lua" }, {
        MPlusForces = {
          dungeonTotal = { [559] = { total = 596, name = "Nexus Point Xenas" } },
          byNpcId = {},
        },
      })
      addon.KillTrack.SetDebugLogger(function(fmt, ...)
        table.insert(driftMessages, string.format(fmt, ...))
      end)
      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_START")
      addon.KillTrack._DispatchEvent("SCENARIO_CRITERIA_UPDATE")
      Assert.Equal(#driftMessages, 1, "drift logger fires once on first divergent read")
      Assert.True(
        driftMessages[1]:find("api=450", 1, true) ~= nil,
        "drift message must include the api total value: " .. driftMessages[1]
      )
      Assert.True(
        driftMessages[1]:find("db=596", 1, true) ~= nil,
        "drift message must include the db total value: " .. driftMessages[1]
      )

      -- Second read with same values must NOT re-trigger the logger.
      addon.KillTrack._DispatchEvent("SCENARIO_CRITERIA_UPDATE")
      Assert.Equal(#driftMessages, 1, "drift logger must suppress repeated identical drifts")
    end)
  end)

  test("KillTrack stays inactive when API total is missing and DB has no entry for the mapID", function()
    local env = BuildKillTrackEnv({ scenario = { quantity = 25, total = 100, mapID = 99999 } })
    env.globals.C_ScenarioInfo.GetCriteriaInfo = function()
      return {
        isWeightedProgress = true,
        totalQuantity = nil,
        quantityString = "25",
        quantity = 25,
      }
    end
    WithGlobals(env.globals, function()
      local addon = LoadAddonModules({ "isiLive_killtrack.lua" }, {
        MPlusForces = {
          dungeonTotal = { [559] = { total = 596 } },
          byNpcId = {},
        },
      })
      addon.KillTrack._DispatchEvent("CHALLENGE_MODE_START")
      local data = addon.KillTrack.GetData()
      Assert.Equal(data.total, 0, "total must be 0 when neither API nor DB provides a value for mapID")
      Assert.Equal(data.percent, 0, "percent must be 0 when total cannot be resolved")
    end)
  end)
end

return function(test, ctx)
  local Assert = ctx.assert
  local WithGlobals = ctx.with_globals
  local LoadAddonModules = ctx.load_modules

  RegisterEventRegistrationTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterStateTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterPullBaselineTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterSubscriberTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterTickerTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterDbTotalAndMapIdTests(test, Assert, WithGlobals, LoadAddonModules)
end
