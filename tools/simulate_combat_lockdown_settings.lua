-- Standalone CLI tool: combat-lockdown defer-and-replay end-to-end simulator.
--
-- Background: WoW 12.0 (Midnight) raises ADDON_ACTION_FORBIDDEN when a tainted
-- code path mutates a protected frame inside an InCombatLockdown window.
-- isiLive's response pattern is uniform across surfaces: producers detect
-- combat lockdown and queue a pending state; the runtime PLAYER_REGEN_ENABLED
-- handler drains that queue once combat ends.
--
-- The drain logic lives in [logic/isiLive_event_handlers_runtime.lua:452-486],
-- HandlePlayerRegenEnabledEvent. Today's coverage hits each ctx-callback in
-- isolation via testmodul/isilive_test_scenarios_event_handlers_runtime_branches.lua,
-- but no test exercises the FULL lifecycle: combat starts -> user toggles
-- multiple settings -> combat ends -> drain order is correct -> raid-mode
-- vetoes pending visibility -> a second combat cycle does not replay
-- already-drained state.
--
-- This simulator stands up a real EventHandlers controller via
-- Fixtures.BuildEventHandlersController, drives PLAYER_REGEN_DISABLED and
-- PLAYER_REGEN_ENABLED through controller:Dispatch, and pins:
--   1. Empty queue: regen-enabled with no pending state is a no-op (no apply
--      calls fire spuriously).
--   2. Single pending source: only the queued surface drains.
--   3. Multiple pending sources: bindings + visibility + width + height all
--      drain in one regen-enabled cycle.
--   4. Raid-override: pending visibility=true is forced to false in raid mode
--      (UC-07 + RULES_LOGIC rule "im Raid bleibt die Main-UI aus").
--   5. Raid-skip-resize: pending height/width are NOT applied in raid mode
--      (early return after the visibility branch).
--   6. Cycle isolation: pending state does not survive an already-fired
--      drain. A second regen-enabled is a no-op.
--   7. Re-entry: enter combat again after a drain, queue NEW state, exit
--      combat -> the second drain only fires the second cycle's state.
--
-- End-to-end discipline: the EventHandlers controller is real,
-- HandlePlayerRegenEnabledEvent is real. Producers (the call sites that
-- enqueue pending state during combat) are modeled as small closures inside
-- this simulator since their concrete implementations live across multiple
-- UI modules (MainFrame.SetVisible, Bindings.ApplyHotkeyBindings,
-- MainFrame.SetHeightSafe, etc.) and standing all of them up here would
-- duplicate testing already done in scenarios/branches files. The PIN here
-- is the drain side, not the queue side.
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

-- The session model: a struct that simulates the production combat-state
-- machinery. Producer closures (attemptToggleVisible, attemptResizeHeight,
-- attemptApplyBindings) check `inCombat` and either apply directly or
-- queue. Consumer closures (wired into ctx) drain.
local function BuildSession()
  local session = {
    inCombat = false,
    raidActive = false,

    pendingBindingApply = false,
    pendingMainFrameVisible = nil,
    pendingMainFrameHeight = nil,
    pendingMainFrameWidth = nil,

    appliedBindings = 0,
    appliedVisibility = {},
    appliedHeight = {},
    appliedWidth = {},
    uiUpdates = 0,
    teleportButtonUpdates = 0,
    centerNoticeRestores = 0,
    kickTrackerEvents = {},
    killTrackEvents = {},
    runtimeTraces = {},
  }

  -- Producer closures: what UI / settings code does at the call site when
  -- the user toggles a setting or the addon wants to mutate the main frame.
  function session.attemptApplyBindings()
    if session.inCombat then
      session.pendingBindingApply = true
      return false
    end
    session.appliedBindings = session.appliedBindings + 1
    return true
  end

  function session.attemptSetVisible(visible)
    if session.inCombat then
      session.pendingMainFrameVisible = visible
      return false
    end
    session.appliedVisibility[#session.appliedVisibility + 1] = visible
    return true
  end

  function session.attemptSetHeight(height)
    if session.inCombat then
      session.pendingMainFrameHeight = height
      return false
    end
    session.appliedHeight[#session.appliedHeight + 1] = height
    return true
  end

  function session.attemptSetWidth(width)
    if session.inCombat then
      session.pendingMainFrameWidth = width
      return false
    end
    session.appliedWidth[#session.appliedWidth + 1] = width
    return true
  end

  -- Consumer closures: wired into ctx, called by the production
  -- HandlePlayerRegenEnabledEvent drain.
  local overrides = {
    isRaidGroup = function()
      return session.raidActive
    end,
    isInChallengeMode = function()
      return false
    end,
    isMainFrameShown = function()
      return true
    end,
    logRuntimeTrace = function(msg)
      session.runtimeTraces[#session.runtimeTraces + 1] = msg
    end,
    handleKickTrackerEvent = function(event)
      session.kickTrackerEvents[#session.kickTrackerEvents + 1] = event
    end,
    handleKillTrackEvent = function(event)
      session.killTrackEvents[#session.killTrackEvents + 1] = event
    end,
    -- Producers expose state to the drain via "get-and-clear" semantics so
    -- the production drain naturally consumes the queue.
    getPendingBindingApply = function()
      local pending = session.pendingBindingApply
      session.pendingBindingApply = false
      return pending
    end,
    applyHotkeyBindings = function()
      session.appliedBindings = session.appliedBindings + 1
    end,
    getPendingMainFrameVisible = function()
      local pending = session.pendingMainFrameVisible
      session.pendingMainFrameVisible = nil
      return pending
    end,
    setMainFrameVisible = function(visible)
      session.appliedVisibility[#session.appliedVisibility + 1] = visible
    end,
    getPendingMainFrameHeight = function()
      local pending = session.pendingMainFrameHeight
      session.pendingMainFrameHeight = nil
      return pending
    end,
    setMainFrameHeightSafe = function(height)
      session.appliedHeight[#session.appliedHeight + 1] = height
    end,
    getPendingMainFrameWidth = function()
      local pending = session.pendingMainFrameWidth
      session.pendingMainFrameWidth = nil
      return pending
    end,
    setMainFrameWidthSafe = function(width)
      session.appliedWidth[#session.appliedWidth + 1] = width
    end,
    updateUI = function()
      session.uiUpdates = session.uiUpdates + 1
    end,
    updateMPlusTeleportButton = function()
      session.teleportButtonUpdates = session.teleportButtonUpdates + 1
    end,
    tryRestoreCenterNoticeTeleportButton = function()
      session.centerNoticeRestores = session.centerNoticeRestores + 1
    end,
  }

  local addon, controller
  Harness.WithGlobals({
    InCombatLockdown = function()
      return session.inCombat
    end,
  }, function()
    addon = Harness.LoadAddonModules({
      "isiLive_event_handlers.lua",
    })
    controller = Fixtures.BuildEventHandlersController(addon.EventHandlers, { value = nil }, {}, overrides)
  end)

  local Unpack = rawget(_G, "unpack") or (type(table) == "table" and rawget(table, "unpack"))

  session.dispatch = function(event, ...)
    local args = { n = select("#", ...), ... }
    Harness.WithGlobals({
      InCombatLockdown = function()
        return session.inCombat
      end,
    }, function()
      if args.n == 0 then
        controller:Dispatch(event)
      else
        controller:Dispatch(event, Unpack(args, 1, args.n))
      end
    end)
  end

  return session
end

-- ----------------------------------------------------------------------
-- Phase 1: empty queue. PLAYER_REGEN_ENABLED with no pending state must
-- not apply anything spurious.
-- ----------------------------------------------------------------------
local function ScenarioEmptyQueueIsNoop()
  print("\n========== Phase 1: empty queue -> regen-enabled is a no-op ==========")
  local session = BuildSession()

  -- Combat start (no pending state queued).
  session.inCombat = true
  session.dispatch("PLAYER_REGEN_DISABLED")

  -- Combat end with empty queue.
  session.inCombat = false
  session.dispatch("PLAYER_REGEN_ENABLED")

  Check(session.appliedBindings == 0, "no bindings applied (empty queue)")
  Check(#session.appliedVisibility == 0, "no visibility applied (empty queue)")
  Check(#session.appliedHeight == 0, "no height applied (empty queue)")
  Check(#session.appliedWidth == 0, "no width applied (empty queue)")
  Check(session.uiUpdates == 1, "updateUI fired once (mainFrameShown=true post-regen)")
  Check(session.teleportButtonUpdates == 1, "teleport button refresh fired once")
end

-- ----------------------------------------------------------------------
-- Phase 2: single pending source. User toggles one setting during combat
-- (e.g., width resize). Combat ends -> only that surface drains.
-- ----------------------------------------------------------------------
local function ScenarioSinglePendingDrains()
  print("\n========== Phase 2: single pending source drains in isolation ==========")
  local session = BuildSession()

  session.inCombat = true
  session.dispatch("PLAYER_REGEN_DISABLED")

  -- Producer: user adjusts width during combat. Caller goes through
  -- attemptSetWidth, which detects combat and queues.
  local applied = session.attemptSetWidth(420)
  Check(applied == false, "attemptSetWidth deferred during combat (returned false)")
  Check(session.pendingMainFrameWidth == 420, "pendingMainFrameWidth queued to 420")
  Check(#session.appliedWidth == 0, "no width applied yet")

  session.inCombat = false
  session.dispatch("PLAYER_REGEN_ENABLED")

  Check(session.appliedWidth[1] == 420, "width 420 applied on regen-enabled")
  Check(#session.appliedHeight == 0, "no height side-effect")
  Check(session.appliedBindings == 0, "no bindings side-effect")
  Check(#session.appliedVisibility == 0, "no visibility side-effect")
  Check(session.pendingMainFrameWidth == nil, "pendingMainFrameWidth cleared after drain")
end

-- ----------------------------------------------------------------------
-- Phase 3: multiple pending sources drain together. Bindings + visibility
-- + height + width all queued. Combat ends -> all drain.
-- ----------------------------------------------------------------------
local function ScenarioMultiplePendingDrainTogether()
  print("\n========== Phase 3: bindings + visibility + height + width all drain ==========")
  local session = BuildSession()

  session.inCombat = true
  session.dispatch("PLAYER_REGEN_DISABLED")

  Check(session.attemptApplyBindings() == false, "attemptApplyBindings deferred")
  Check(session.attemptSetVisible(true) == false, "attemptSetVisible deferred")
  Check(session.attemptSetHeight(300) == false, "attemptSetHeight deferred")
  Check(session.attemptSetWidth(420) == false, "attemptSetWidth deferred")

  Check(session.pendingBindingApply == true, "pendingBindingApply queued")
  Check(session.pendingMainFrameVisible == true, "pendingMainFrameVisible queued")
  Check(session.pendingMainFrameHeight == 300, "pendingMainFrameHeight queued")
  Check(session.pendingMainFrameWidth == 420, "pendingMainFrameWidth queued")

  session.inCombat = false
  session.dispatch("PLAYER_REGEN_ENABLED")

  Check(session.appliedBindings == 1, "bindings applied once")
  Check(session.appliedVisibility[1] == true, "visibility applied as true")
  Check(session.appliedHeight[1] == 300, "height applied as 300")
  Check(session.appliedWidth[1] == 420, "width applied as 420")

  -- All pending fields cleared after drain.
  Check(session.pendingBindingApply == false, "pendingBindingApply cleared")
  Check(session.pendingMainFrameVisible == nil, "pendingMainFrameVisible cleared")
  Check(session.pendingMainFrameHeight == nil, "pendingMainFrameHeight cleared")
  Check(session.pendingMainFrameWidth == nil, "pendingMainFrameWidth cleared")
end

-- ----------------------------------------------------------------------
-- Phase 4: raid-mode override on visibility. User queued
-- pendingMainFrameVisible=true during combat, but the group switched to
-- raid mode in the meantime. Production must clamp to false (RULES_LOGIC
-- rule 2: "im Raid bleibt die Main-UI aus").
-- ----------------------------------------------------------------------
local function ScenarioRaidOverridesPendingVisibility()
  print("\n========== Phase 4: raid mode forces pending visibility=true to false ==========")
  local session = BuildSession()

  session.inCombat = true
  session.dispatch("PLAYER_REGEN_DISABLED")

  session.attemptSetVisible(true)
  Check(session.pendingMainFrameVisible == true, "pendingMainFrameVisible=true queued during combat")

  -- Group converted to raid while in combat.
  session.raidActive = true
  session.inCombat = false
  session.dispatch("PLAYER_REGEN_ENABLED")

  Check(session.appliedVisibility[1] == false, "raid-mode clamped pending visibility to false")
  Check(#session.appliedVisibility == 1, "exactly one setMainFrameVisible call (no double-apply)")
end

-- ----------------------------------------------------------------------
-- Phase 5: raid-mode skips pending height/width. The early-return in
-- HandlePlayerRegenEnabledEvent (after the visibility branch) means raid
-- mode does NOT drain pending height or width. Pin that the queue stays
-- intact and applies on the next non-raid drain.
-- ----------------------------------------------------------------------
local function ScenarioRaidSkipsPendingResize()
  print("\n========== Phase 5: raid mode skips pending height/width drain ==========")
  local session = BuildSession()

  session.inCombat = true
  session.dispatch("PLAYER_REGEN_DISABLED")

  session.attemptSetHeight(250)
  session.attemptSetWidth(400)

  session.raidActive = true
  session.inCombat = false
  session.dispatch("PLAYER_REGEN_ENABLED")

  -- Bindings DO drain (no raid guard on that branch).
  -- Visibility branch only fires when pendingVisible is non-nil; not queued here.
  -- Height/width drain is AFTER the IsRaidModeActive early-return.
  Check(#session.appliedHeight == 0, "raid mode: height NOT applied")
  Check(#session.appliedWidth == 0, "raid mode: width NOT applied")
  Check(session.pendingMainFrameHeight == 250, "pendingMainFrameHeight retained for next drain")
  Check(session.pendingMainFrameWidth == 400, "pendingMainFrameWidth retained for next drain")

  -- Group leaves raid; another regen-enabled cycle (e.g. PLAYER_REGEN_ENABLED
  -- replayed after group transition) drains the retained queue.
  session.raidActive = false
  session.dispatch("PLAYER_REGEN_ENABLED")

  Check(session.appliedHeight[1] == 250, "post-raid drain applies retained height")
  Check(session.appliedWidth[1] == 400, "post-raid drain applies retained width")
end

-- ----------------------------------------------------------------------
-- Phase 6: cycle isolation. After a drain, the queue is empty. A second
-- regen-enabled with no new producer activity is a no-op (does not
-- re-apply already-drained state).
-- ----------------------------------------------------------------------
local function ScenarioCycleIsolation()
  print("\n========== Phase 6: drained state does not survive into next regen-enabled ==========")
  local session = BuildSession()

  session.inCombat = true
  session.dispatch("PLAYER_REGEN_DISABLED")
  session.attemptApplyBindings()
  session.attemptSetVisible(true)
  session.inCombat = false
  session.dispatch("PLAYER_REGEN_ENABLED")

  Check(session.appliedBindings == 1, "first cycle: bindings applied once")
  Check(#session.appliedVisibility == 1, "first cycle: visibility applied once")

  -- Second regen-enabled with no new combat-defer activity.
  session.dispatch("PLAYER_REGEN_ENABLED")

  Check(session.appliedBindings == 1, "second cycle: bindings NOT re-applied (queue was drained)")
  Check(#session.appliedVisibility == 1, "second cycle: visibility NOT re-applied")
end

-- ----------------------------------------------------------------------
-- Phase 7: re-entry. Combat -> drain -> combat -> NEW state -> drain.
-- The second drain must only fire the SECOND cycle's queued state, not
-- replay the first cycle's already-applied state.
-- ----------------------------------------------------------------------
local function ScenarioReEntryCleanQueue()
  print("\n========== Phase 7: re-entry into combat starts with clean queue ==========")
  local session = BuildSession()

  -- Cycle 1: bindings only.
  session.inCombat = true
  session.dispatch("PLAYER_REGEN_DISABLED")
  session.attemptApplyBindings()
  session.inCombat = false
  session.dispatch("PLAYER_REGEN_ENABLED")
  Check(session.appliedBindings == 1, "cycle 1: bindings applied")

  -- Cycle 2: width only (a different surface).
  session.inCombat = true
  session.dispatch("PLAYER_REGEN_DISABLED")
  session.attemptSetWidth(380)
  session.inCombat = false
  session.dispatch("PLAYER_REGEN_ENABLED")

  Check(session.appliedWidth[1] == 380, "cycle 2: width applied")
  Check(session.appliedBindings == 1, "cycle 2: bindings NOT replayed from cycle 1")
  Check(#session.appliedHeight == 0, "cycle 2: no spurious height")
end

-- ----------------------------------------------------------------------
-- Phase 8: regen-disabled hooks. PLAYER_REGEN_DISABLED dispatches its
-- own work (combat-fade trigger, KillTrack notification) — pin that
-- those fire on the right event.
-- ----------------------------------------------------------------------
local function ScenarioRegenDisabledHooks()
  print("\n========== Phase 8: regen-disabled fires KillTrack notification ==========")
  local session = BuildSession()

  session.inCombat = true
  session.dispatch("PLAYER_REGEN_DISABLED")

  Check(
    session.killTrackEvents[1] == "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_DISABLED forwarded to handleKillTrackEvent"
  )
  Check(#session.kickTrackerEvents == 0, "kick tracker NOT fired on regen-disabled (only on regen-enabled)")
end

ScenarioEmptyQueueIsNoop()
ScenarioSinglePendingDrains()
ScenarioMultiplePendingDrainTogether()
ScenarioRaidOverridesPendingVisibility()
ScenarioRaidSkipsPendingResize()
ScenarioCycleIsolation()
ScenarioReEntryCleanQueue()
ScenarioRegenDisabledHooks()

if failures > 0 then
  print(string.format("\nCombat-lockdown defer-and-replay simulator failed: %d check(s) failed", failures))
  os.exit(1)
end

print("\nCombat-lockdown defer-and-replay simulator passed.")
