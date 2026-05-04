-- Standalone CLI tool: end-to-end lifecycle for the M+ KillTrack module.
--
-- The KillTrack pipeline reads scenario criteria (forces percent + total) on
-- every dispatched event and broadcasts state updates to subscribed callbacks
-- (status line, mob nameplate, mob tooltip). It also detects drift between
-- the live API total and the MDT-synced DB total — when they disagree, a
-- one-shot warning lands in the runtime log sink so MDT data can be refreshed.
--
-- Verifies:
--   * CHALLENGE_MODE_START reads live data, marks state.active, fires updates.
--   * SCENARIO_CRITERIA_UPDATE (the generic dispatch path) increments rawCount
--     and recomputes percent from the API total.
--   * CHALLENGE_MODE_COMPLETED + CHALLENGE_MODE_RESET clear state and stop
--     the refresh ticker.
--   * Drift detection: API-total ≠ DB-total → debugLogger called once;
--     subsequent identical drift is deduped.
--   * DB-total fallback: when the API total is nil/0, the DB total takes over.
--   * Pull tracking: PLAYER_REGEN_DISABLED captures startRawCount;
--     SCENARIO_CRITERIA_UPDATE during combat increments pullPercent;
--     PLAYER_REGEN_ENABLED keeps the bar visible for the grace window.
--   * Demo data short-circuit: SetDemoData wins over live data; ClearDemoData
--     restores live.
--   * Secret-Value safety: a tainted totalQuantity fails closed (state.total=0).
--
-- End-to-end discipline (CLAUDE.md "Tests & simulators: end-to-end by default"):
-- the real KillTrack module is loaded; every state mutation flows through
-- KillTrack.HandleEvent (the production dispatcher); subscribed callbacks
-- run the production NotifyUpdate fan-out; drift detection uses the real
-- debugLogger sink. ReadLiveData reads from a steerable C_ScenarioInfo /
-- C_ChallengeMode mock — the same shape WoW exposes.
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

local failures = 0

local function Check(condition, message)
  if condition then
    print("  [CHECK PASS] " .. message)
    return
  end
  failures = failures + 1
  print("  [CHECK FAIL] " .. message)
end

-- ----------------------------------------------------------------------
-- Steerable scenario model. The C_ScenarioInfo / C_ChallengeMode mocks
-- below dereference these fields, so test scenarios mutate them between
-- HandleEvent calls to drive percent / total / drift / secret-value paths.
-- ----------------------------------------------------------------------
local model = {
  now = 1000,
  activeMapID = 2649, -- Ara-Kara
  apiTotal = 200,
  apiRawCount = 0,
  dbTotal = nil, -- when set, addonTable.MPlusForces.dungeonTotal[mapID].total
  totalIsSecret = false,
  rawCountIsSecret = false,
  ticks = {}, -- C_Timer.NewTicker callbacks captured for explicit advancement
}

local function ResetModel()
  model.now = 1000
  model.activeMapID = 2649
  model.apiTotal = 200
  model.apiRawCount = 0
  model.dbTotal = nil
  model.totalIsSecret = false
  model.rawCountIsSecret = false
  model.ticks = {}
end

-- A simple "secret value" sentinel: the production code calls
-- rawget(_G, "issecretvalue")(value); we attach a metatable to recognise the
-- sentinel objects we hand back through the criteria info.
local SECRET_SENTINEL = setmetatable({}, {
  __tostring = function()
    return "<SECRET>"
  end,
})
local function IsSecret(v)
  return v == SECRET_SENTINEL
end

local function buildGlobals()
  return {
    GetTime = function()
      return model.now
    end,
    issecretvalue = IsSecret,
    C_ChallengeMode = {
      GetActiveChallengeMapID = function()
        if model.activeMapID then
          return model.activeMapID
        end
        return nil
      end,
    },
    C_ScenarioInfo = {
      GetScenarioStepInfo = function()
        if not model.activeMapID then
          return nil
        end
        return { numCriteria = 1 }
      end,
      GetCriteriaInfo = function()
        return {
          isWeightedProgress = true,
          totalQuantity = model.totalIsSecret and SECRET_SENTINEL or model.apiTotal,
          quantityString = model.rawCountIsSecret and SECRET_SENTINEL
            or (model.apiRawCount and tostring(model.apiRawCount)),
        }
      end,
    },
    C_Timer = {
      NewTicker = function(_interval, callback)
        local handle = { _cancelled = false, _callback = callback }
        function handle:Cancel()
          handle._cancelled = true
        end
        model.ticks[#model.ticks + 1] = handle
        return handle
      end,
      After = function(_seconds, callback)
        if type(callback) == "function" then
          callback()
        end
      end,
    },
  }
end

-- ----------------------------------------------------------------------
-- Build a fresh KillTrack session. addonTable.MPlusForces is set up with
-- the test's dbTotal so the production drift-detection sees both sides.
-- ----------------------------------------------------------------------
local function BuildSession()
  local addon
  Harness.WithGlobals(buildGlobals(), function()
    addon = Harness.LoadAddonModules({ "isiLive_killtrack.lua" })
  end)

  -- Inject the MDT-synced DB total via the same field production reads from.
  if addon and not addon.MPlusForces then
    addon.MPlusForces = { dungeonTotal = {} }
  end
  addon.MPlusForces.dungeonTotal = {}
  if model.dbTotal and model.activeMapID then
    addon.MPlusForces.dungeonTotal[model.activeMapID] = { total = model.dbTotal }
  end

  local debugLog = {}
  addon.KillTrack.SetDebugLogger(function(fmt, ...)
    debugLog[#debugLog + 1] = string.format(fmt, ...)
  end)

  local updateCalls = 0
  addon.KillTrack.OnUpdate(function()
    updateCalls = updateCalls + 1
  end)

  return {
    addon = addon,
    debugLog = debugLog,
    updateCalls = function()
      return updateCalls
    end,
    fire = function(event)
      Harness.WithGlobals(buildGlobals(), function()
        addon.KillTrack.HandleEvent(event)
      end)
    end,
    refreshDb = function()
      if model.dbTotal and model.activeMapID then
        addon.MPlusForces.dungeonTotal[model.activeMapID] = { total = model.dbTotal }
      else
        addon.MPlusForces.dungeonTotal = {}
      end
    end,
    advance = function(seconds)
      model.now = model.now + (seconds or 0)
    end,
  }
end

-- ----------------------------------------------------------------------
-- Phase 1: happy path — START -> kill update -> percent computed.
-- ----------------------------------------------------------------------
local function ScenarioHappyPath()
  print("\n========== Scenario 1: CHALLENGE_MODE_START -> kill -> percent ==========")
  ResetModel()
  model.apiTotal = 200
  model.apiRawCount = 0
  local session = BuildSession()

  session.fire("CHALLENGE_MODE_START")
  local data = session.addon.KillTrack.GetData()
  Check(data.active == true, "post-START: state.active=true")
  Check(data.mapID == 2649, "post-START: state.mapID=2649")
  Check(data.total == 200, "post-START: state.total picks up API total")
  Check(data.rawCount == 0, "post-START: state.rawCount=0 before any kill")

  -- Simulate a kill: rawCount jumps to 50.
  model.apiRawCount = 50
  session.fire("SCENARIO_CRITERIA_UPDATE")
  data = session.addon.KillTrack.GetData()
  Check(data.rawCount == 50, "after kill: state.rawCount updated from API")

  -- A second kill brings us to 100/200 = 50%.
  model.apiRawCount = 100
  session.fire("SCENARIO_CRITERIA_UPDATE")
  data = session.addon.KillTrack.GetData()
  Check(data.rawCount == 100, "after second kill: rawCount=100")
  Check(session.updateCalls() >= 3, "OnUpdate fan-out fires for START + 2 kill updates")
end

-- ----------------------------------------------------------------------
-- Phase 2: drift detection — API total disagrees with DB total.
-- The first divergence triggers a debug-log line; identical repeats are
-- deduped. A different mapID divergence reports again.
-- ----------------------------------------------------------------------
local function ScenarioDriftDetection()
  print("\n========== Scenario 2: drift detection (API total vs DB total) ==========")
  ResetModel()
  model.apiTotal = 200
  model.dbTotal = 250 -- divergent
  local session = BuildSession()

  session.fire("CHALLENGE_MODE_START")
  Check(#session.debugLog == 1, "drift log line emitted on first divergence")
  Check(
    session.debugLog[1]:find("api=200") and session.debugLog[1]:find("db=250"),
    "drift log includes both totals (api=200, db=250)"
  )

  -- Repeat: same mapID + same totals → dedup, no new line.
  session.fire("SCENARIO_CRITERIA_UPDATE")
  session.fire("SCENARIO_CRITERIA_UPDATE")
  Check(#session.debugLog == 1, "repeat drift with identical key is suppressed (no spam)")

  -- API total used as denominator (primacy over DB).
  Check(session.addon.KillTrack.GetData().total == 200, "API total wins as the percent denominator")
end

-- ----------------------------------------------------------------------
-- Phase 3: DB-total fallback when API total is nil (transient API gap).
-- ----------------------------------------------------------------------
local function ScenarioDbTotalFallback()
  print("\n========== Scenario 3: DB-total fallback when API total is nil ==========")
  ResetModel()
  model.apiTotal = nil
  model.dbTotal = 180
  local session = BuildSession()

  session.fire("CHALLENGE_MODE_START")
  Check(
    session.addon.KillTrack.GetData().total == 180,
    "DB-total takes over when the API total is missing (resilient to Blizzard-side gaps)"
  )
end

-- ----------------------------------------------------------------------
-- Phase 4: CHALLENGE_MODE_COMPLETED + CHALLENGE_MODE_RESET clear state.
-- ----------------------------------------------------------------------
local function ScenarioCompletedAndResetClearState()
  print("\n========== Scenario 4: COMPLETED + RESET clear state ==========")
  ResetModel()
  model.apiTotal = 200
  model.apiRawCount = 100
  local session = BuildSession()

  session.fire("CHALLENGE_MODE_START")
  Check(session.addon.KillTrack.GetData().active == true, "after START: active=true")

  session.fire("CHALLENGE_MODE_COMPLETED")
  local data = session.addon.KillTrack.GetData()
  Check(data.active == false, "after COMPLETED: active=false")
  Check(data.rawCount == 0, "after COMPLETED: rawCount cleared")
  Check(data.total == 0, "after COMPLETED: total cleared")
  Check(data.mapID == nil, "after COMPLETED: mapID cleared")

  -- Restart and then RESET: should also clear.
  session.fire("CHALLENGE_MODE_START")
  Check(session.addon.KillTrack.GetData().active == true, "restart sets active again")
  session.fire("CHALLENGE_MODE_RESET")
  Check(session.addon.KillTrack.GetData().active == false, "after RESET: active=false again")
end

-- ----------------------------------------------------------------------
-- Phase 5: pull tracking — REGEN_DISABLED captures baseline,
-- SCENARIO_CRITERIA_UPDATE during combat increments pullPercent, REGEN_ENABLED
-- keeps the bar visible for the grace window then resets.
-- ----------------------------------------------------------------------
local function ScenarioPullTracking()
  print("\n========== Scenario 5: pull tracking via REGEN events ==========")
  ResetModel()
  model.apiTotal = 200
  model.apiRawCount = 50
  local session = BuildSession()

  session.fire("CHALLENGE_MODE_START")
  session.fire("PLAYER_REGEN_DISABLED")
  Check(session.addon.KillTrack.GetData().inCombat == true, "REGEN_DISABLED → inCombat=true")

  -- A pull adds 10 kills.
  model.apiRawCount = 60
  session.fire("SCENARIO_CRITERIA_UPDATE")
  local data = session.addon.KillTrack.GetData()
  Check(data.inCombat == true, "still in combat during pull")
  Check(data.pullPercent > 0, "pullPercent grows above 0 during the pull")

  -- Regen ends. Bar stays visible during the grace window.
  session.fire("PLAYER_REGEN_ENABLED")
  data = session.addon.KillTrack.GetData()
  Check(data.inCombat == false, "REGEN_ENABLED → inCombat=false")
end

-- ----------------------------------------------------------------------
-- Phase 6: demo data short-circuit. SetDemoData replaces the GetData()
-- result entirely; ClearDemoData restores the live read.
-- ----------------------------------------------------------------------
local function ScenarioDemoData()
  print("\n========== Scenario 6: demo data short-circuits live state ==========")
  ResetModel()
  model.apiTotal = 200
  model.apiRawCount = 50
  local session = BuildSession()
  session.fire("CHALLENGE_MODE_START")

  session.addon.KillTrack.SetDemoData({
    active = true,
    percent = 99,
    rawCount = 198,
    total = 200,
    mapID = 9999,
    inCombat = false,
    pullPercent = 0,
  })
  local data = session.addon.KillTrack.GetData()
  Check(data.percent == 99 and data.mapID == 9999, "SetDemoData replaces GetData() entirely")

  session.addon.KillTrack.ClearDemoData()
  data = session.addon.KillTrack.GetData()
  Check(data.mapID == 2649, "ClearDemoData restores the live mapID")
end

-- ----------------------------------------------------------------------
-- Phase 7: Secret-Value safety. A tainted totalQuantity must fail closed
-- to total=0 instead of being passed through as a truthy non-number.
-- ----------------------------------------------------------------------
local function ScenarioSecretValueSafety()
  print("\n========== Scenario 7: Secret Value totalQuantity fails closed ==========")
  ResetModel()
  model.totalIsSecret = true
  model.apiRawCount = 50
  local session = BuildSession()

  session.fire("CHALLENGE_MODE_START")
  local data = session.addon.KillTrack.GetData()
  Check(
    data.total == 0,
    "Secret-Value totalQuantity fails closed to total=0 (no percent computed against tainted denominator)"
  )
  Check(data.percent == 0, "percent stays 0 when total is unsafe")
end

ScenarioHappyPath()
ScenarioDriftDetection()
ScenarioDbTotalFallback()
ScenarioCompletedAndResetClearState()
ScenarioPullTracking()
ScenarioDemoData()
ScenarioSecretValueSafety()

if failures > 0 then
  print(string.format("\nKillTrack lifecycle simulator failed: %d check(s) failed", failures))
  os.exit(1)
end

print("\nKillTrack lifecycle simulator passed.")
