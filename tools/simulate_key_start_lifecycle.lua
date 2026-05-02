-- Standalone CLI tool: simulates CHALLENGE_MODE_START through the real
-- EventHandlers controller and verifies the key-start side effects stay wired.
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

local function Append(list, value)
  list[#list + 1] = value
end

local function Count(list, value)
  local n = 0
  for _, item in ipairs(list or {}) do
    if item == value then
      n = n + 1
    end
  end
  return n
end

local function IndexOf(list, value)
  for i, item in ipairs(list or {}) do
    if item == value then
      return i
    end
  end
  return nil
end

local function FormatEvents(events)
  if #events == 0 then
    return "-"
  end
  return table.concat(events, " -> ")
end

local function BuildController(opts)
  opts = opts or {}
  local events = {}
  local visibility = {}
  local damageMeterResets = 0
  local state = {
    activeJoinedKeyMapID = 161,
    readyCheckActive = true,
    nameplateRefreshes = 0,
    timerEvents = {},
    killTrackEvents = {},
    combatEvents = {},
  }

  local globals = {
    C_DamageMeter = {
      IsDamageMeterAvailable = function()
        Append(events, "damageMeter.available")
        return opts.damageMeterAvailable ~= false
      end,
      ResetAllCombatSessions = function()
        Append(events, "damageMeter.reset")
        damageMeterResets = damageMeterResets + 1
      end,
    },
  }

  local controller
  Harness.WithGlobals(globals, function()
    local addon = Harness.LoadAddonModules({ "isiLive_event_handlers.lua" })
    controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, {}, {
      isRaidGroup = function()
        return opts.inRaid == true
      end,
      isRosterCollapsed = function()
        return opts.rosterCollapsed == true
      end,
      shouldAutoCloseMainFrame = function()
        return opts.autoClose == true
      end,
      setMainFrameVisible = function(visible)
        Append(events, "ui.visible=" .. tostring(visible))
        visibility[#visibility + 1] = visible == true
      end,
      handleMplusTimerEvent = function(event)
        Append(events, "timer." .. tostring(event))
        state.timerEvents[#state.timerEvents + 1] = event
      end,
      handleKillTrackEvent = function(event)
        Append(events, "killTrack." .. tostring(event))
        state.killTrackEvents[#state.killTrackEvents + 1] = event
        if event == "CHALLENGE_MODE_START" then
          Append(events, "nameplate.refreshFromKillTrack")
          state.nameplateRefreshes = state.nameplateRefreshes + 1
        end
      end,
      handleCombatEventsEvent = function(event)
        Append(events, "combatEvents." .. tostring(event))
        state.combatEvents[#state.combatEvents + 1] = event
      end,
      resetKickStats = function()
        Append(events, "kick.reset")
      end,
      setReadyCheckActive = function(active)
        Append(events, "readyCheck.active=" .. tostring(active))
        state.readyCheckActive = active == true
      end,
      captureRioBaselineSnapshot = function()
        Append(events, "rio.captureBaseline")
      end,
      setActiveJoinedKeyMapID = function(value)
        Append(events, "joinedKeyMap=" .. tostring(value))
        state.activeJoinedKeyMapID = value
      end,
      checkIfEnteredTargetDungeon = function()
        Append(events, "target.checkEntered")
      end,
      updateLeaderButtons = function()
        Append(events, "ui.leaderButtons")
      end,
      updateStatusLine = function()
        Append(events, "ui.statusLine")
      end,
      updateMPlusTeleportButton = function()
        Append(events, "ui.teleportButton")
      end,
      logRuntimeTrace = function(message)
        Append(events, "trace:" .. tostring(message))
      end,
    })
  end)

  return {
    controller = controller,
    dispatch = function(event)
      Harness.WithGlobals(globals, function()
        controller:Dispatch(event)
      end)
    end,
    events = events,
    visibility = visibility,
    state = state,
    damageMeterResets = function()
      return damageMeterResets
    end,
  }
end

local function PrintSummary(label, sim)
  print("---- " .. label)
  print("  events              = " .. FormatEvents(sim.events))
  print("  damageMeterResets   = " .. tostring(sim.damageMeterResets()))
  print("  readyCheckActive    = " .. tostring(sim.state.readyCheckActive))
  print("  activeJoinedKeyMapID= " .. tostring(sim.state.activeJoinedKeyMapID))
  print("  nameplateRefreshes  = " .. tostring(sim.state.nameplateRefreshes))
end

local function CheckCommonKeyStart(sim)
  Check(Count(sim.events, "timer.CHALLENGE_MODE_START") == 1, "M+ timer receives CHALLENGE_MODE_START exactly once")
  Check(
    Count(sim.events, "killTrack.CHALLENGE_MODE_START") == 1,
    "KillTrack receives CHALLENGE_MODE_START exactly once"
  )
  Check(
    Count(sim.events, "combatEvents.CHALLENGE_MODE_START") == 1,
    "CombatEvents receives CHALLENGE_MODE_START exactly once"
  )
  Check(Count(sim.events, "kick.reset") == 1, "kick stats reset on key start")
  Check(sim.state.readyCheckActive == false, "ready-check state is cleared on key start")
  Check(sim.damageMeterResets() == 1, "Blizzard damage meter reset runs once when available")
  Check(Count(sim.events, "rio.captureBaseline") == 1, "RIO baseline capture runs once")
  Check(sim.state.activeJoinedKeyMapID == nil, "active joined-key map is cleared")
  Check(Count(sim.events, "target.checkEntered") == 1, "target-dungeon entry check runs once")
  Check(Count(sim.events, "ui.leaderButtons") == 1, "leader buttons refresh once")
  Check(Count(sim.events, "ui.statusLine") == 1, "status line refreshes once")
  Check(Count(sim.events, "ui.teleportButton") == 1, "M+ teleport button refreshes once")
  Check(sim.state.nameplateRefreshes == 1, "KillTrack key-start path refreshes nameplates once")

  local timerIndex = IndexOf(sim.events, "timer.CHALLENGE_MODE_START") or 0
  local killIndex = IndexOf(sim.events, "killTrack.CHALLENGE_MODE_START") or 0
  local combatIndex = IndexOf(sim.events, "combatEvents.CHALLENGE_MODE_START") or 0
  local rioIndex = IndexOf(sim.events, "rio.captureBaseline") or 0
  local targetIndex = IndexOf(sim.events, "target.checkEntered") or 0
  Check(
    timerIndex > 0 and killIndex > timerIndex and combatIndex > killIndex,
    "timer -> KillTrack -> CombatEvents order is preserved"
  )
  Check(rioIndex > 0 and targetIndex > rioIndex, "target-dungeon check happens after RIO baseline capture")
end

local function ScenarioDefaultNoAutoClose()
  print("\n========== Scenario 1: key start, default no auto-close ==========")
  local sim = BuildController({ autoClose = false })
  sim.dispatch("CHALLENGE_MODE_START")
  PrintSummary("after CHALLENGE_MODE_START", sim)
  CheckCommonKeyStart(sim)
  Check(#sim.visibility == 0, "main frame is not auto-closed by default")
end

local function ScenarioAutoClose()
  print("\n========== Scenario 2: key start with auto-close enabled ==========")
  local sim = BuildController({ autoClose = true })
  sim.dispatch("CHALLENGE_MODE_START")
  PrintSummary("after CHALLENGE_MODE_START", sim)
  CheckCommonKeyStart(sim)
  Check(#sim.visibility == 1 and sim.visibility[1] == false, "main frame auto-closes when option is enabled")
end

local function ScenarioCollapsedSkipsAutoClose()
  print("\n========== Scenario 3: key start with auto-close enabled but roster collapsed ==========")
  local sim = BuildController({ autoClose = true, rosterCollapsed = true })
  sim.dispatch("CHALLENGE_MODE_START")
  PrintSummary("after CHALLENGE_MODE_START", sim)
  CheckCommonKeyStart(sim)
  Check(#sim.visibility == 0, "collapsed roster suppresses auto-close visibility mutation")
end

local function ScenarioRaidHardOff()
  print("\n========== Scenario 4: raid hard-off suppresses key-start lifecycle ==========")
  local sim = BuildController({ autoClose = true, inRaid = true })
  sim.dispatch("CHALLENGE_MODE_START")
  PrintSummary("after CHALLENGE_MODE_START", sim)
  Check(#sim.events == 0, "raid mode suppresses all challenge-start side effects")
  Check(sim.damageMeterResets() == 0, "raid mode does not reset the damage meter")
  Check(sim.state.readyCheckActive == true, "raid-suppressed key start leaves ready-check state untouched")
  Check(sim.state.activeJoinedKeyMapID == 161, "raid-suppressed key start leaves joined-key map untouched")
end

local function Run()
  ScenarioDefaultNoAutoClose()
  ScenarioAutoClose()
  ScenarioCollapsedSkipsAutoClose()
  ScenarioRaidHardOff()

  if failures > 0 then
    print(string.format("\nKey-start lifecycle simulator failed: %d check(s) failed", failures))
    os.exit(1)
  end

  print("\nKey-start lifecycle simulator passed.")
end

Run()
