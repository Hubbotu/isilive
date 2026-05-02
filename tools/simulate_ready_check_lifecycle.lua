-- Standalone CLI tool: simulates the full ready-check lifecycle (READY_CHECK →
-- READY_CHECK_CONFIRM → READY_CHECK_FINISHED → hold expiry) and prints the
-- background-color state of each roster row at every step. Verifies that the
-- 20-second hold actually keeps the row decorated after the ready check ended,
-- and pinpoints whether the bug is on the event-handler side, the state side,
-- or the render side.
---@diagnostic disable-next-line: undefined-global
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
local Fixtures = LoadLocal("testmodul/isilive_test_fixtures.lua")

-- Simulated state: ready-check active flag, per-unit hold timestamps,
-- per-unit live status (what GetReadyCheckStatus would return), and a
-- monotonic clock we manually advance between steps.
local sim = {
  now = 100,
  isReadyCheckActive = false,
  readyCheckStatus = {}, -- unit → "ready"|"notready"|"waiting"|nil
  readyUntilByUnit = {},
  declinedUntilByUnit = {},
  scheduledTimers = {}, -- list of { fireAt, callback }
}

local function Tick(deltaSeconds)
  sim.now = sim.now + deltaSeconds
  -- Fire any timer whose deadline has passed (in scheduled order).
  local pending = sim.scheduledTimers
  sim.scheduledTimers = {}
  for _, timer in ipairs(pending) do
    if timer.fireAt <= sim.now then
      timer.callback()
    else
      table.insert(sim.scheduledTimers, timer)
    end
  end
end

local roster = {
  player = { name = "Tank", class = "WARRIOR", role = "TANK" },
  party1 = { name = "Healer", class = "PRIEST", role = "HEALER" },
  party2 = { name = "Dps1", class = "MAGE", role = "DAMAGER" },
  party3 = { name = "Dps2", class = "ROGUE", role = "DAMAGER" },
  party4 = { name = "Dps3", class = "WARLOCK", role = "DAMAGER" },
}

-- rolePriority / unitPriority are referenced when this simulator is later
-- extended to call BuildOrderedRoster directly. Currently kept for future use.

local function BuildController()
  local addon = Harness.LoadAddonModules({ "isiLive_event_handlers.lua" })
  local entryRef = { value = nil }
  local counters = {}
  local controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, entryRef, counters, {
    setReadyCheckActive = function(value)
      sim.isReadyCheckActive = value and true or false
    end,
    isReadyCheckActive = function()
      return sim.isReadyCheckActive
    end,
    getTime = function()
      return sim.now
    end,
    getRoster = function()
      return roster
    end,
    setReadyCheckReadyUntil = function(unit, value)
      sim.readyUntilByUnit[unit] = value
    end,
    setReadyCheckDeclinedUntil = function(unit, value)
      sim.declinedUntilByUnit[unit] = value
    end,
    getReadyCheckReadyUntil = function(unit)
      return sim.readyUntilByUnit[unit]
    end,
    getReadyCheckDeclinedUntil = function(unit)
      return sim.declinedUntilByUnit[unit]
    end,
    clearAllReadyCheckReady = function()
      sim.readyUntilByUnit = {}
    end,
    clearAllReadyCheckDeclined = function()
      sim.declinedUntilByUnit = {}
    end,
    clearExpiredReadyCheckReady = function(currentTime)
      local changed = false
      for unit, untilTime in pairs(sim.readyUntilByUnit) do
        if untilTime <= currentTime then
          sim.readyUntilByUnit[unit] = nil
          changed = true
        end
      end
      return changed
    end,
    clearExpiredReadyCheckDeclined = function(currentTime)
      local changed = false
      for unit, untilTime in pairs(sim.declinedUntilByUnit) do
        if untilTime <= currentTime then
          sim.declinedUntilByUnit[unit] = nil
          changed = true
        end
      end
      return changed
    end,
    timerAfter = function(delaySeconds, callback)
      table.insert(sim.scheduledTimers, { fireAt = sim.now + delaySeconds, callback = callback })
    end,
  })
  return controller, counters
end

local function LoadRoster()
  return Harness.LoadAddonModules({ "isiLive_roster.lua" })
end

-- Builds the display data for every roster member with the ready-check hooks
-- routed to the simulated state. Returns a table { unit = backgroundColor|nil }.
local function SnapshotBackgrounds()
  local result = {}
  Harness.WithGlobals({
    GetReadyCheckStatus = function(unit)
      return sim.readyCheckStatus[unit]
    end,
    RAID_CLASS_COLORS = {
      WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
      PRIEST = { r = 1, g = 1, b = 1 },
      MAGE = { r = 0.41, g = 0.8, b = 0.94 },
      ROGUE = { r = 1, g = 0.96, b = 0.41 },
      WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
    },
    UnitIsConnected = function()
      return true
    end,
  }, function()
    local addon = LoadRoster()
    for unit, info in pairs(roster) do
      local data = addon.Roster.BuildDisplayData(info, {
        unit = unit,
        isReadyCheckActive = sim.isReadyCheckActive,
        getReadyCheckReadyUntil = function(u)
          return sim.readyUntilByUnit[u]
        end,
        getReadyCheckDeclinedUntil = function(u)
          return sim.declinedUntilByUnit[u]
        end,
        getTime = function()
          return sim.now
        end,
      })
      result[unit] = {
        status = data.readyCheckStatus,
        color = data.readyCheckBackgroundColor,
        markup = data.readyCheckMarkup,
      }
    end
  end)
  return result
end

local function ColorLabel(color)
  if type(color) ~= "table" then
    return "(none)"
  end
  -- Match against READY_CHECK_BACKGROUND_COLORS in roster.lua
  if color[1] == 0.08 then
    return "GREEN(ready)"
  elseif color[1] == 0.48 then
    return "RED(notready)"
  elseif color[1] == 0.55 then
    return "YELLOW(waiting)"
  end
  return string.format("rgba(%.2f,%.2f,%.2f,%.2f)", color[1], color[2], color[3], color[4])
end

local function PrintSnapshot(label)
  local snap = SnapshotBackgrounds()
  local order = { "player", "party1", "party2", "party3", "party4" }
  print(string.format("---- %s [t=%d, active=%s]", label, sim.now, tostring(sim.isReadyCheckActive)))
  for _, unit in ipairs(order) do
    local info = snap[unit] or {}
    print(
      string.format(
        "  %-7s name=%-7s status=%-9s bg=%-15s readyUntil=%s declinedUntil=%s",
        unit,
        roster[unit].name,
        tostring(info.status or "-"),
        ColorLabel(info.color),
        tostring(sim.readyUntilByUnit[unit] or "-"),
        tostring(sim.declinedUntilByUnit[unit] or "-")
      )
    )
  end
end

local function ResetSim()
  sim.now = 100
  sim.isReadyCheckActive = false
  sim.readyCheckStatus = {}
  sim.readyUntilByUnit = {}
  sim.declinedUntilByUnit = {}
  sim.scheduledTimers = {}
end

local function ScenarioHappyPath()
  print("\n========== Scenario 1: happy path (mixed responses) ==========")
  ResetSim()
  local controller = BuildController()

  PrintSnapshot("0. baseline (no ready check)")

  controller:Dispatch("READY_CHECK")
  for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
    sim.readyCheckStatus[unit] = "waiting"
  end
  PrintSnapshot("1. READY_CHECK fired (all waiting)")

  Tick(2)
  sim.readyCheckStatus.player = "ready"
  controller:Dispatch("READY_CHECK_CONFIRM", "player", "ready")
  sim.readyCheckStatus.party1 = "ready"
  controller:Dispatch("READY_CHECK_CONFIRM", "party1", "ready")
  sim.readyCheckStatus.party2 = "notready"
  controller:Dispatch("READY_CHECK_CONFIRM", "party2", "notready")
  -- party3 and party4 remain "waiting" (no answer)
  PrintSnapshot("2. confirms received (player+party1=ready, party2=notready, party3+4=no answer)")

  Tick(3)
  -- READY_CHECK_FINISHED simulates the WoW client clearing live status:
  for unit in pairs(sim.readyCheckStatus) do
    sim.readyCheckStatus[unit] = nil
  end
  controller:Dispatch("READY_CHECK_FINISHED")
  PrintSnapshot("3. READY_CHECK_FINISHED → hold should be active for 20s")

  Tick(5)
  PrintSnapshot("4. +5s into hold (still within 20s window)")

  Tick(10)
  PrintSnapshot("5. +15s into hold (still within 20s window)")

  Tick(6)
  PrintSnapshot("6. +21s after FINISHED (hold expired, timers fired)")
end

local function ScenarioRapidRecheck()
  print("\n========== Scenario 2: a second READY_CHECK fires while a hold is still active ==========")
  ResetSim()
  local controller = BuildController()

  controller:Dispatch("READY_CHECK")
  sim.readyCheckStatus.player = "ready"
  controller:Dispatch("READY_CHECK_CONFIRM", "player", "ready")
  sim.readyCheckStatus.party1 = "notready"
  controller:Dispatch("READY_CHECK_CONFIRM", "party1", "notready")
  for unit in pairs(sim.readyCheckStatus) do
    sim.readyCheckStatus[unit] = nil
  end
  controller:Dispatch("READY_CHECK_FINISHED")
  PrintSnapshot("1. first ready check finished → hold active")

  Tick(5)
  -- Second ready check starts mid-hold. The current code wipes all holds
  -- via ResetReadyCheckDeclinedTracking — verify behavior is what we want.
  controller:Dispatch("READY_CHECK")
  for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
    sim.readyCheckStatus[unit] = "waiting"
  end
  PrintSnapshot("2. second READY_CHECK fired (holds wiped, all waiting again)")
end

local function ScenarioFinishWithNoConfirms()
  print("\n========== Scenario 3: nobody answers the ready check (all 'waiting' on FINISHED) ==========")
  ResetSim()
  local controller = BuildController()

  controller:Dispatch("READY_CHECK")
  for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
    sim.readyCheckStatus[unit] = "waiting"
  end
  PrintSnapshot("1. READY_CHECK fired (all waiting)")

  Tick(30) -- typical WoW 30s ready-check timeout
  for unit in pairs(sim.readyCheckStatus) do
    sim.readyCheckStatus[unit] = nil
  end
  controller:Dispatch("READY_CHECK_FINISHED")
  PrintSnapshot("2. READY_CHECK_FINISHED → 'no answer' members should be visible somehow for 20s")
  print("    NOTE per user spec: 'grau = keine antwort' — but the current code")
  print("    promotes unanswered units to DECLINED → red (notready), not gray.")
end

local function ScenarioRenderAfterFinish()
  print("\n========== Scenario 4: a generic UI re-render happens 1s AFTER FINISHED ==========")
  print("(this is the bug the user reports: 'background overwritten right after readycheck')")
  ResetSim()
  local controller = BuildController()

  controller:Dispatch("READY_CHECK")
  sim.readyCheckStatus.player = "ready"
  controller:Dispatch("READY_CHECK_CONFIRM", "player", "ready")
  for unit in pairs(sim.readyCheckStatus) do
    sim.readyCheckStatus[unit] = nil
  end
  controller:Dispatch("READY_CHECK_FINISHED")
  PrintSnapshot("1. READY_CHECK_FINISHED → hold active")

  -- Simulate any other event triggering a render: GROUP_ROSTER_UPDATE,
  -- INSPECT_READY etc would all call BuildDisplayData via RenderRoster.
  -- This snapshot is exactly what a re-render would compute right after.
  Tick(1)
  PrintSnapshot("2. +1s, simulating a generic UI rerender (e.g. GROUP_ROSTER_UPDATE)")

  Tick(2)
  PrintSnapshot("3. +3s, another rerender")

  Tick(15)
  PrintSnapshot("4. +18s, just before hold expiry")
end

ScenarioHappyPath()
ScenarioRapidRecheck()
ScenarioFinishWithNoConfirms()
ScenarioRenderAfterFinish()
