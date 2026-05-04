-- Standalone CLI tool: simulates the full inspect pipeline (EnqueueInspect ->
-- OnUpdate dispatch -> NotifyInspect -> INSPECT_READY -> OnInspectReady ->
-- roster.ilvl/rio/spec update) and pins the WoW 12.0 (Midnight) bug class
-- that v0.9.212 fixed.
--
-- 12.0 reality the production code (logic/isiLive_inspect.lua) guards against:
--   * C_PaperDollInfo.GetInspectItemLevel("party*") returns 0 for many seconds
--     after INSPECT_READY fires — writing that 0 would clobber any prior good
--     ilvl. The handler must short-circuit on `ilvl <= 0`.
--   * GetInspectItemLevel("player") returns 0 unconditionally. The own-player
--     branch must fall back to getOwnAverageItemLevel (which calls
--     C_Item.GetAverageItemLevel locally).
--   * InspectLoop in factory.lua skips OnUpdate during InCombatLockdown(), so
--     inspects pause during pulls but flow during dungeon downtime — this
--     keeps a /reload mid-key populating ilvl/RIO/spec instead of stalling.
--
-- End-to-end discipline (CLAUDE.md "Tests & simulators: end-to-end by default"):
-- the real Inspect.CreateController is loaded; EnqueueInspect / OnUpdate /
-- OnInspectReady are the production entries; cache hits / queue / retry-queue
-- state lives in the controller's own tables. NotifyInspect is captured via
-- a global mock so we can assert which units were dispatched.
--
-- COMPONENT-ONLY exception (justified): the InspectLoop wrapper from
-- factory.lua:397-411 (InCombatLockdown short-circuit + 0.25s timer) is
-- replicated inline in `runInspectLoopTick` below. The production wrapper
-- depends on a fully wired ctx (eventHandlersController, runtimeLogController,
-- frame bridge) that this test cannot reasonably stand up. The replica is
-- 4 lines and mirrors the real check exactly; if the production check
-- changes (e.g. switches from InCombatLockdown to a different gate), this
-- simulator must follow.
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
-- WoW-globals model: every Blizzard surface the inspect path touches.
-- The test scenarios mutate this table between phases to exercise the
-- 12.0 Secret-Value / API-returns-0 edge cases.
-- ----------------------------------------------------------------------
local model = {
  now = 100,
  inCombatLockdown = false,
  unitGUIDs = {}, -- unit -> guid string
  unitVisible = {}, -- unit -> bool
  unitInspectable = {}, -- unit -> bool (CanInspect)
  inspectItemLevelByUnit = {}, -- unit -> ilvl (what GetInspectItemLevel returns)
  notifyInspectCalls = {}, -- list of units NotifyInspect was called with
  ownIlvl = nil, -- value getOwnAverageItemLevel returns
}

local function ResetModel()
  model.now = 100
  model.inCombatLockdown = false
  model.unitGUIDs = {}
  model.unitVisible = {}
  model.unitInspectable = {}
  model.inspectItemLevelByUnit = {}
  model.notifyInspectCalls = {}
  model.ownIlvl = nil
end

local function SetUnit(unit, guid, opts)
  opts = opts or {}
  model.unitGUIDs[unit] = guid
  model.unitVisible[unit] = opts.visible ~= false
  model.unitInspectable[unit] = opts.inspectable ~= false
end

local globals = {
  GetTime = function()
    return model.now
  end,
  UnitGUID = function(unit)
    return model.unitGUIDs[unit]
  end,
  UnitExists = function(unit)
    return model.unitGUIDs[unit] ~= nil
  end,
  UnitIsVisible = function(unit)
    return model.unitVisible[unit] == true
  end,
  CanInspect = function(unit)
    return model.unitInspectable[unit] == true
  end,
  NotifyInspect = function(unit)
    model.notifyInspectCalls[#model.notifyInspectCalls + 1] = unit
  end,
  InCombatLockdown = function()
    return model.inCombatLockdown == true
  end,
  C_PaperDollInfo = {
    GetInspectItemLevel = function(unit)
      return model.inspectItemLevelByUnit[unit] or 0
    end,
  },
}

-- ----------------------------------------------------------------------
-- Build a real Inspect.CreateController and the small InspectLoop wrapper
-- replica. SetDependencies-style closures (getUnitRio, getInspectSpecName,
-- getPlayerSpecName, getOwnAverageItemLevel) are passed at OnInspectReady
-- call time, mirroring how event_handlers_runtime.lua wires them.
-- ----------------------------------------------------------------------
local function BuildSession(opts)
  opts = opts or {}
  local addon
  Harness.WithGlobals(globals, function()
    addon = Harness.LoadAddonModules({ "isiLive_inspect.lua" })
  end)
  local controller = addon.Inspect.CreateController({
    inspectTimeout = 2,
    retryInterval = 5,
    inspectDelay = 1,
    sendOwnKeySnapshot = function() end,
  })

  local sessionGetters = {
    getUnitRio = function(unit)
      return opts.getUnitRio and opts.getUnitRio(unit) or nil
    end,
    getInspectSpecName = function(unit)
      return opts.getInspectSpecName and opts.getInspectSpecName(unit) or nil
    end,
    getPlayerSpecName = function()
      return opts.getPlayerSpecName and opts.getPlayerSpecName() or nil
    end,
    getOwnAverageItemLevel = function()
      return model.ownIlvl
    end,
  }

  return {
    addon = addon,
    controller = controller,
    enqueue = function(unit, roster)
      Harness.WithGlobals(globals, function()
        controller.EnqueueInspect(unit, roster)
      end)
    end,
    -- Mirror of factory.lua:397-411 InspectLoop: short-circuit during
    -- InCombatLockdown(), otherwise call OnUpdate. The 0.25s timer is
    -- elided since tests advance time explicitly.
    runInspectLoopTick = function()
      Harness.WithGlobals(globals, function()
        if InCombatLockdown() then
          return
        end
        controller.OnUpdate()
      end)
    end,
    fireInspectReady = function(guid, roster)
      local result
      Harness.WithGlobals(globals, function()
        result = controller.OnInspectReady(
          guid,
          roster,
          sessionGetters.getUnitRio,
          sessionGetters.getInspectSpecName,
          sessionGetters.getPlayerSpecName,
          sessionGetters.getOwnAverageItemLevel
        )
      end)
      return result
    end,
    advance = function(seconds)
      model.now = model.now + (seconds or 0)
    end,
  }
end

-- ----------------------------------------------------------------------
-- Phase 1: happy path — enqueue party1, dispatch via OnUpdate, fire
-- INSPECT_READY, roster gets a real ilvl/rio/spec write.
-- ----------------------------------------------------------------------
local function ScenarioHappyPath()
  print("\n========== Scenario 1: happy-path inspect roundtrip ==========")
  ResetModel()
  SetUnit("party1", "Player-Bob")
  model.inspectItemLevelByUnit.party1 = 615

  local session = BuildSession({
    getUnitRio = function(unit)
      return unit == "party1" and 3210 or nil
    end,
    getInspectSpecName = function(unit)
      return unit == "party1" and "Devastation" or nil
    end,
  })
  local roster = { party1 = { name = "Bob", realm = "Realm" } }

  session.enqueue("party1", roster)
  Check(#session.controller.inspectQueue == 1, "EnqueueInspect adds party1 to the inspect queue")

  session.advance(2) -- past the 1s inspectDelay
  session.runInspectLoopTick()
  Check(
    #model.notifyInspectCalls == 1 and model.notifyInspectCalls[1] == "party1",
    "OnUpdate dispatches NotifyInspect('party1') after the inspectDelay window"
  )
  Check(session.controller.isInspecting == "party1", "controller.isInspecting tracks the in-flight unit")

  local changed = session.fireInspectReady("Player-Bob", roster)
  Check(changed == true, "OnInspectReady reports dataChanged=true on first successful inspect")
  Check(roster.party1.ilvl == 615, "roster.party1.ilvl gets the real value from C_PaperDollInfo")
  Check(roster.party1.rio == 3210, "roster.party1.rio gets the real value from getUnitRio")
  Check(roster.party1.spec == "Devastation", "roster.party1.spec gets the real value from getInspectSpecName")
  Check(roster.party1._localIlvlFresh == true, "_localIlvlFresh marker prevents sync-backfill from clobbering")
  Check(session.controller.isInspecting == nil, "controller.isInspecting is cleared after OnInspectReady")
end

-- ----------------------------------------------------------------------
-- Phase 2: 12.0 bug pin — INSPECT_READY arrives but GetInspectItemLevel
-- returns 0. Production code must NOT overwrite the prior good ilvl.
-- ----------------------------------------------------------------------
local function ScenarioInspectReadyZeroIlvl()
  print("\n========== Scenario 2: INSPECT_READY with ilvl=0 must NOT overwrite ==========")
  ResetModel()
  SetUnit("party1", "Player-Bob")
  model.inspectItemLevelByUnit.party1 = 0 -- 12.0 transient response

  local session = BuildSession()
  local roster = { party1 = { name = "Bob", realm = "Realm", ilvl = 615, _localIlvlFresh = true } }

  session.enqueue("party1", roster)
  session.advance(2)
  session.runInspectLoopTick()
  session.fireInspectReady("Player-Bob", roster)

  Check(roster.party1.ilvl == 615, "prior good ilvl is preserved when API returns 0 (12.0 fix v0.9.212)")
end

-- ----------------------------------------------------------------------
-- Phase 3: self-fallback — INSPECT_READY for "player" with API=0 must
-- fall back to getOwnAverageItemLevel.
-- ----------------------------------------------------------------------
local function ScenarioPlayerSelfFallback()
  print("\n========== Scenario 3: player self-fallback to getOwnAverageItemLevel ==========")
  ResetModel()
  SetUnit("player", "Player-Self")
  model.inspectItemLevelByUnit.player = 0 -- 12.0 returns 0 for self always
  model.ownIlvl = 612

  local session = BuildSession({
    getPlayerSpecName = function()
      return "Brewmaster"
    end,
  })
  local roster = { player = { name = "Self", realm = "Realm" } }

  session.enqueue("player", roster)
  session.advance(2)
  session.runInspectLoopTick()
  session.fireInspectReady("Player-Self", roster)

  Check(
    roster.player.ilvl == 612,
    "player ilvl falls back to getOwnAverageItemLevel when GetInspectItemLevel returns 0 (v0.9.212 fix)"
  )
  Check(roster.player.spec == "Brewmaster", "player spec falls back to getPlayerSpecName when API returns nothing")
end

-- ----------------------------------------------------------------------
-- Phase 4: InCombatLockdown pause. Production InspectLoop short-circuits
-- OnUpdate during combat — inspects must remain queued, not dispatched.
-- ----------------------------------------------------------------------
local function ScenarioCombatLockdownPause()
  print("\n========== Scenario 4: InCombatLockdown pauses dispatch (mid-key downtime fix) ==========")
  ResetModel()
  SetUnit("party1", "Player-Bob")
  SetUnit("party2", "Player-Carol")
  model.inspectItemLevelByUnit.party1 = 600
  model.inspectItemLevelByUnit.party2 = 605

  local session = BuildSession()
  local roster = {
    party1 = { name = "Bob", realm = "Realm" },
    party2 = { name = "Carol", realm = "Realm" },
  }

  session.enqueue("party1", roster)
  session.enqueue("party2", roster)
  Check(#session.controller.inspectQueue == 2, "two units enqueued")

  -- Combat starts → next tick must NOT call NotifyInspect.
  model.inCombatLockdown = true
  session.advance(2)
  session.runInspectLoopTick()
  Check(
    #model.notifyInspectCalls == 0,
    "OnUpdate is skipped while InCombatLockdown() == true (factory.lua:406-408 mirror)"
  )
  Check(#session.controller.inspectQueue == 2, "inspect queue is preserved across the combat-paused tick")

  -- Combat ends → next tick drains.
  model.inCombatLockdown = false
  session.advance(2)
  session.runInspectLoopTick()
  Check(#model.notifyInspectCalls == 1, "first unit dispatched after combat ends")
  Check(model.notifyInspectCalls[1] == "party1", "FIFO preserved: party1 dispatches first")
end

-- ----------------------------------------------------------------------
-- Phase 5: cache hit — second EnqueueInspect for the same unit (with all
-- three caches populated) short-circuits without a new NotifyInspect.
-- ----------------------------------------------------------------------
local function ScenarioCacheHit()
  print("\n========== Scenario 5: cache hit short-circuits second inspect ==========")
  ResetModel()
  SetUnit("party1", "Player-Bob")
  model.inspectItemLevelByUnit.party1 = 615

  local session = BuildSession({
    getUnitRio = function()
      return 3210
    end,
    getInspectSpecName = function()
      return "Devastation"
    end,
  })
  local roster = { party1 = { name = "Bob", realm = "Realm" } }

  -- First inspect: populates all three caches.
  session.enqueue("party1", roster)
  session.advance(2)
  session.runInspectLoopTick()
  session.fireInspectReady("Player-Bob", roster)
  Check(session.controller.ilvlCache["Player-Bob"] == 615, "ilvlCache populated from first inspect")
  Check(session.controller.rioCache["Player-Bob"] == 3210, "rioCache populated from first inspect")
  Check(session.controller.specCache["Player-Bob"] == "Devastation", "specCache populated from first inspect")

  -- Reset roster (e.g. raid->party transition cleared it) and re-enqueue.
  -- All three caches hit → no new NotifyInspect.
  local notifyCountBefore = #model.notifyInspectCalls
  roster = { party1 = { name = "Bob", realm = "Realm" } }
  session.enqueue("party1", roster)
  session.advance(2)
  session.runInspectLoopTick()
  Check(
    #model.notifyInspectCalls == notifyCountBefore,
    "second EnqueueInspect short-circuits: cached values fill the new roster entry without a new NotifyInspect"
  )
  Check(roster.party1.ilvl == 615, "cached ilvl flows back into the fresh roster entry")
  Check(roster.party1.rio == 3210, "cached rio flows back into the fresh roster entry")
  Check(roster.party1.spec == "Devastation", "cached spec flows back into the fresh roster entry")
end

-- ----------------------------------------------------------------------
-- Phase 6: ghost members are skipped — never enqueued, never inspected.
-- ----------------------------------------------------------------------
local function ScenarioGhostSkip()
  print("\n========== Scenario 6: ghost roster members are never enqueued ==========")
  ResetModel()
  SetUnit("party1", "Player-Bob")
  model.inspectItemLevelByUnit.party1 = 615

  local session = BuildSession()
  local roster = {
    party1 = { name = "Bob", realm = "Realm", isGhost = true },
  }

  session.enqueue("party1", roster)
  Check(
    #session.controller.inspectQueue == 0,
    "ghost-flagged roster entries do not enter the inspect queue (avoids wasted NotifyInspect on stale units)"
  )
end

-- ----------------------------------------------------------------------
-- Phase 7: inspect timeout → retry queue. If INSPECT_READY never arrives
-- within inspectTimeout (2s), the unit moves to retryQueue.
-- ----------------------------------------------------------------------
local function ScenarioInspectTimeout()
  print("\n========== Scenario 7: inspect timeout moves unit to retry queue ==========")
  ResetModel()
  SetUnit("party1", "Player-Bob")

  local session = BuildSession()
  local roster = { party1 = { name = "Bob", realm = "Realm" } }

  session.enqueue("party1", roster)
  session.advance(2)
  session.runInspectLoopTick()
  Check(session.controller.isInspecting == "party1", "party1 is in flight")

  -- No INSPECT_READY arrives. Advance past the 2s timeout.
  session.advance(3)
  session.runInspectLoopTick()
  Check(session.controller.isInspecting == nil, "isInspecting cleared by timeout")
  Check(#session.controller.retryQueue == 1, "timed-out unit moved to the retry queue")
  Check(session.controller.retryQueue[1].unit == "party1", "retry-queue entry preserves the unit identity")
end

ScenarioHappyPath()
ScenarioInspectReadyZeroIlvl()
ScenarioPlayerSelfFallback()
ScenarioCombatLockdownPause()
ScenarioCacheHit()
ScenarioGhostSkip()
ScenarioInspectTimeout()

if failures > 0 then
  print(string.format("\nInspect-pipeline simulator failed: %d check(s) failed", failures))
  os.exit(1)
end

print("\nInspect-pipeline simulator passed.")
