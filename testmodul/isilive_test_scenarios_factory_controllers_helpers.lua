---@diagnostic disable: undefined-global

-- Scenarios for the ctx-helper initializers in
-- factory/isiLive_factory_controllers.lua, invoked via the exported
-- FI.InitializeFactoryRuntimeHelpers(ctx). This covers three of the
-- four internal Initialize* sub-functions:
--
--   * InitializeGameAPIHelpers: ReadyCheck delegates, challenge-map
--     reader, party-instance + portal-navigator resolvers.
--   * InitializeRuntimeStateDelegates: was-in-group / was-raid-group /
--     was-group-leader / roster getter+setter + NormalizePlayerKey.
--   * InitializeRioHelpers: BuildRosterInfoPlayerKey, RestoreRioBaseline,
--     ClearRioBaselineSnapshot, CaptureRioBaselineSnapshot,
--     EnableRioDeltaDisplay, GetRioDeltaForRosterInfo.
--
-- The fourth sub-function (InitializeStatusAndOperationalHelpers, 340
-- lines at factory_controllers.lua:264-602) is left to a follow-up
-- pass - it wires status/target/teleport callbacks with a much wider
-- dependency surface.
--
-- The existing factory_primary / factory_secondary scenarios already
-- exercise end-to-end flows; this file targets the sub-function
-- surfaces that those flows happen to skip.

local function BuildRuntimeStateStub()
  local state = {
    storage = {
      wasInGroup = false,
      wasRaidGroup = false,
      wasGroupLeader = false,
      roster = {},
      readyCheckActive = false,
      readyCheckReady = {},
      readyCheckDeclined = {},
      rioBaselineByKey = {},
      hasRioBaselineSnapshot = false,
      rioDeltaDisplayEnabled = false,
      rioBaselineClears = 0,
    },
  }
  local s = state.storage

  state.GetWasInGroup = function()
    return s.wasInGroup
  end
  state.SetWasInGroup = function(v)
    s.wasInGroup = v
  end
  state.GetWasRaidGroup = function()
    return s.wasRaidGroup
  end
  state.SetWasRaidGroup = function(v)
    s.wasRaidGroup = v
  end
  state.GetWasGroupLeader = function()
    return s.wasGroupLeader
  end
  state.SetWasGroupLeader = function(v)
    s.wasGroupLeader = v
  end
  state.GetRoster = function()
    return s.roster
  end
  state.SetRoster = function(v)
    s.roster = v
  end
  state.IsReadyCheckActive = function()
    return s.readyCheckActive
  end
  state.SetReadyCheckActive = function(v)
    s.readyCheckActive = v
  end
  state.GetReadyCheckReadyUntil = function(unit)
    return s.readyCheckReady[unit]
  end
  state.SetReadyCheckReadyUntil = function(unit, v)
    s.readyCheckReady[unit] = v
  end
  state.ClearAllReadyCheckReady = function()
    s.readyCheckReady = {}
  end
  state.ClearExpiredReadyCheckReady = function(now)
    local cleared = false
    for u, until_ in pairs(s.readyCheckReady) do
      if until_ and until_ <= now then
        s.readyCheckReady[u] = nil
        cleared = true
      end
    end
    return cleared
  end
  state.GetReadyCheckDeclinedUntil = function(unit)
    return s.readyCheckDeclined[unit]
  end
  state.SetReadyCheckDeclinedUntil = function(unit, v)
    s.readyCheckDeclined[unit] = v
  end
  state.ClearAllReadyCheckDeclined = function()
    s.readyCheckDeclined = {}
  end
  state.ClearExpiredReadyCheckDeclined = function(now)
    local cleared = false
    for u, until_ in pairs(s.readyCheckDeclined) do
      if until_ and until_ <= now then
        s.readyCheckDeclined[u] = nil
        cleared = true
      end
    end
    return cleared
  end
  state.SetRioBaselineByPlayerKey = function(v)
    s.rioBaselineByKey = v or {}
  end
  state.GetRioBaselineByPlayerKey = function()
    return s.rioBaselineByKey
  end
  state.HasRioBaselineSnapshot = function()
    return s.hasRioBaselineSnapshot
  end
  state.SetHasRioBaselineSnapshot = function(v)
    s.hasRioBaselineSnapshot = v and true or false
  end
  state.IsRioDeltaDisplayEnabled = function()
    return s.rioDeltaDisplayEnabled
  end
  state.SetRioDeltaDisplayEnabled = function(v)
    s.rioDeltaDisplayEnabled = v and true or false
  end
  state.ClearRioBaseline = function()
    s.rioBaselineByKey = {}
    s.hasRioBaselineSnapshot = false
    s.rioDeltaDisplayEnabled = false
    s.rioBaselineClears = s.rioBaselineClears + 1
  end

  return state, s
end

local function BuildModulesStub(overrides)
  overrides = overrides or {}
  return {
    sync = {
      NormalizePlayerKey = overrides.NormalizePlayerKey or function(name, realm)
        return (name or "") .. "-" .. (realm or "")
      end,
    },
    teleport = overrides.teleport,
  }
end

local function BuildCtx(runtimeState, modules, overrides)
  overrides = overrides or {}
  return {
    modules = modules,
    runtimeState = runtimeState,
    GetUnitRio = overrides.GetUnitRio or function()
      return nil
    end,
  }
end

local function InitializeHelpers(ctx, addonTable)
  addonTable._FactoryInternal.InitializeFactoryRuntimeHelpers(ctx)
end

return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  local function Load()
    return LoadAddonModules({ "isiLive_factory_controllers.lua" })
  end

  -- =====================================================
  -- InitializeGameAPIHelpers
  -- =====================================================

  test("factory_controllers: GetActiveChallengeMapID returns nil when C_ChallengeMode is absent", function()
    local addon = Load()
    local rs = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({ C_ChallengeMode = false }, function()
      InitializeHelpers(c, addon)
      Assert.Nil(c.GetActiveChallengeMapID(), "missing C_ChallengeMode must resolve to nil")
    end)
  end)

  test("factory_controllers: GetActiveChallengeMapID forwards the pcalled API result", function()
    local addon = Load()
    local rs = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals(
      { C_ChallengeMode = {
        GetActiveChallengeMapID = function()
          return 2649
        end,
      } },
      function()
        InitializeHelpers(c, addon)
        Assert.Equal(c.GetActiveChallengeMapID(), 2649, "API result must be forwarded")
      end
    )
  end)

  test("factory_controllers: GetActiveChallengeMapID returns nil when API raises", function()
    local addon = Load()
    local rs = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({
      C_ChallengeMode = {
        GetActiveChallengeMapID = function()
          error("boom", 0)
        end,
      },
    }, function()
      InitializeHelpers(c, addon)
      Assert.Nil(c.GetActiveChallengeMapID(), "pcall failure must resolve to nil")
    end)
  end)

  test("factory_controllers: ready-check delegates forward to runtimeState", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    c.SetReadyCheckActive(true)
    Assert.Equal(c.IsReadyCheckActive(), true, "SetReadyCheckActive must propagate to runtimeState")
    Assert.Equal(storage.readyCheckActive, true, "state storage must reflect the set value")
    c.SetReadyCheckReadyUntil("player", 123)
    Assert.Equal(c.GetReadyCheckReadyUntil("player"), 123, "ready-until getter/setter must round-trip")
    c.SetReadyCheckReadyUntil("party1", 50)
    Assert.Equal(c.ClearExpiredReadyCheckReady(100), true, "expired entries must be cleared and reported")
    Assert.Nil(c.GetReadyCheckReadyUntil("party1"), "expired ready entry must be gone")
    Assert.Equal(c.GetReadyCheckReadyUntil("player"), 123, "future ready entry must survive")
    c.ClearAllReadyCheckReady()
    Assert.Nil(c.GetReadyCheckReadyUntil("player"), "ClearAllReadyCheckReady must wipe all entries")
  end)

  test("factory_controllers: declined-check delegates forward to runtimeState", function()
    local addon = Load()
    local rs = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    c.SetReadyCheckDeclinedUntil("party2", 42)
    Assert.Equal(c.GetReadyCheckDeclinedUntil("party2"), 42, "declined-until setter/getter must round-trip")
    c.SetReadyCheckDeclinedUntil("party3", 10)
    Assert.Equal(c.ClearExpiredReadyCheckDeclined(20), true, "expired declined entries must be reported cleared")
    Assert.Nil(c.GetReadyCheckDeclinedUntil("party3"), "expired declined entry must be gone")
    c.ClearAllReadyCheckDeclined()
    Assert.Nil(c.GetReadyCheckDeclinedUntil("party2"), "ClearAllReadyCheckDeclined must wipe all entries")
  end)

  test("factory_controllers: IsInPartyInstance returns true only for party instance type", function()
    local addon = Load()
    local rs = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    local instanceType = "party"
    WithGlobals({
      GetInstanceInfo = function()
        return "Name", instanceType
      end,
    }, function()
      InitializeHelpers(c, addon)
      Assert.Equal(c.IsInPartyInstance(), true, "party instance must resolve to true")
      instanceType = "raid"
      Assert.Equal(c.IsInPartyInstance(), false, "raid instance must resolve to false")
      instanceType = "none"
      Assert.Equal(c.IsInPartyInstance(), false, "none instance must resolve to false")
    end)
  end)

  test("factory_controllers: IsPortalNavigatorEnabled defaults to true when IsiLiveDB is absent", function()
    local addon = Load()
    local rs = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    -- rawset explicitly to nil because WithGlobals iterates stubs via
    -- pairs(), which cannot express "set this key to nil" - the
    -- production code checks `dbRef == nil`, not `dbRef == false`.
    local previous = rawget(_G, "IsiLiveDB")
    rawset(_G, "IsiLiveDB", nil)
    local ok, err = pcall(function()
      WithGlobals({}, function()
        InitializeHelpers(c, addon)
        Assert.Equal(c.IsPortalNavigatorEnabled(), true, "missing DB must keep navigator enabled by default")
      end)
    end)
    rawset(_G, "IsiLiveDB", previous)
    if not ok then
      error(err, 0)
    end
  end)

  test("factory_controllers: IsPortalNavigatorEnabled respects explicit DB disable", function()
    local addon = Load()
    local rs = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({ IsiLiveDB = { showPortalNavigator = false } }, function()
      InitializeHelpers(c, addon)
      Assert.Equal(c.IsPortalNavigatorEnabled(), false, "explicit showPortalNavigator=false must disable")
    end)
  end)

  test("factory_controllers: IsPortalNavigatorEnabled keeps enabled when DB has no override", function()
    local addon = Load()
    local rs = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({ IsiLiveDB = {} }, function()
      InitializeHelpers(c, addon)
      Assert.Equal(c.IsPortalNavigatorEnabled(), true, "missing flag must stay enabled")
    end)
  end)

  -- =====================================================
  -- InitializeRuntimeStateDelegates
  -- =====================================================

  test("factory_controllers: was-in-group delegate round-trips via runtimeState", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    c.SetWasInGroup(true)
    Assert.Equal(storage.wasInGroup, true, "SetWasInGroup must store through runtimeState")
    Assert.Equal(c.GetWasInGroup(), true, "GetWasInGroup must read from runtimeState")
  end)

  test("factory_controllers: was-raid-group delegate round-trips", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    c.SetWasRaidGroup(true)
    Assert.Equal(storage.wasRaidGroup, true, "SetWasRaidGroup must store through runtimeState")
    Assert.Equal(c.GetWasRaidGroup(), true, "GetWasRaidGroup must read from runtimeState")
  end)

  test("factory_controllers: was-group-leader delegate round-trips", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    c.SetWasGroupLeader(true)
    Assert.Equal(storage.wasGroupLeader, true, "SetWasGroupLeader must store through runtimeState")
    Assert.Equal(c.GetWasGroupLeader(), true, "GetWasGroupLeader must read from runtimeState")
  end)

  test("factory_controllers: roster delegate round-trips", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    local newRoster = { player = { name = "P" } }
    c.SetRoster(newRoster)
    Assert.Equal(storage.roster, newRoster, "SetRoster must store through runtimeState")
    Assert.Equal(c.GetRoster(), newRoster, "GetRoster must read from runtimeState")
  end)

  test("factory_controllers: NormalizePlayerKey delegates to sync module", function()
    local addon = Load()
    local rs = BuildRuntimeStateStub()
    local captured
    local modules = BuildModulesStub({
      NormalizePlayerKey = function(name, realm)
        captured = { name = name, realm = realm }
        return "NORMALIZED"
      end,
    })
    local c = BuildCtx(rs, modules)
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    Assert.Equal(c.NormalizePlayerKey("Alice", "Draenor"), "NORMALIZED", "return value must come from sync module")
    Assert.Equal(captured.name, "Alice", "name must be forwarded unchanged")
    Assert.Equal(captured.realm, "Draenor", "realm must be forwarded unchanged")
  end)

  -- =====================================================
  -- InitializeRioHelpers
  -- =====================================================

  test("factory_controllers: BuildRosterInfoPlayerKey returns nil for non-table input", function()
    local addon = Load()
    local rs = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    Assert.Nil(c.BuildRosterInfoPlayerKey(nil), "nil input must resolve to nil key")
    Assert.Nil(c.BuildRosterInfoPlayerKey("not-a-table"), "string input must resolve to nil key")
    Assert.Nil(c.BuildRosterInfoPlayerKey(42), "number input must resolve to nil key")
  end)

  test("factory_controllers: BuildRosterInfoPlayerKey returns nil for missing or empty name", function()
    local addon = Load()
    local rs = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    Assert.Nil(c.BuildRosterInfoPlayerKey({}), "missing name must resolve to nil")
    Assert.Nil(c.BuildRosterInfoPlayerKey({ name = "" }), "empty name must resolve to nil")
    Assert.Nil(c.BuildRosterInfoPlayerKey({ name = 42 }), "non-string name must resolve to nil")
  end)

  test("factory_controllers: BuildRosterInfoPlayerKey normalizes name+realm via NormalizePlayerKey", function()
    local addon = Load()
    local rs = BuildRuntimeStateStub()
    local modules = BuildModulesStub({
      NormalizePlayerKey = function(name, realm)
        return (name or "?") .. "@" .. (realm or "?")
      end,
    })
    local c = BuildCtx(rs, modules)
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    Assert.Equal(c.BuildRosterInfoPlayerKey({ name = "Alice", realm = "Draenor" }), "Alice@Draenor")
    Assert.Equal(c.BuildRosterInfoPlayerKey({ name = "Bob" }), "Bob@?", "missing realm forwards as nil")
  end)

  test(
    "factory_controllers: RestoreRioBaseline loads from IsiLiveDB and enables display when snapshot exists",
    function()
      local addon = Load()
      local rs, storage = BuildRuntimeStateStub()
      local c = BuildCtx(rs, BuildModulesStub())
      local db = { rioBaseline = { ["Alice-Draenor"] = 3400 } }
      WithGlobals({ IsiLiveDB = db }, function()
        InitializeHelpers(c, addon)
        storage.hasRioBaselineSnapshot = true
        c.RestoreRioBaseline()
      end)
      Assert.Equal(storage.rioBaselineByKey["Alice-Draenor"], 3400, "baseline must be loaded from DB")
      Assert.Equal(storage.rioDeltaDisplayEnabled, true, "delta display must be enabled when snapshot exists")
    end
  )

  test("factory_controllers: RestoreRioBaseline is a no-op when IsiLiveDB lacks a baseline", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({ IsiLiveDB = {} }, function()
      InitializeHelpers(c, addon)
      c.RestoreRioBaseline()
    end)
    Assert.Equal(storage.rioDeltaDisplayEnabled, false, "no baseline must not enable delta display")
  end)

  test("factory_controllers: ClearRioBaselineSnapshot clears runtimeState and DB", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    local db = { rioBaseline = { ["Alice-Draenor"] = 3400 } }
    WithGlobals({ IsiLiveDB = db }, function()
      InitializeHelpers(c, addon)
      c.ClearRioBaselineSnapshot()
    end)
    Assert.Equal(storage.rioBaselineClears, 1, "runtimeState.ClearRioBaseline must be called once")
    Assert.Nil(db.rioBaseline, "DB rioBaseline field must be cleared")
  end)

  test("factory_controllers: CaptureRioBaselineSnapshot snapshots the current roster by player key", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    storage.roster = {
      player = { name = "Alice", realm = "Draenor", rio = 3400 },
      party1 = { name = "Bob", realm = "Draenor", rio = 2800 },
    }
    local c = BuildCtx(rs, BuildModulesStub())
    local db = {}
    WithGlobals({ IsiLiveDB = db }, function()
      InitializeHelpers(c, addon)
      c.CaptureRioBaselineSnapshot()
    end)
    Assert.Equal(storage.rioBaselineByKey["Alice-Draenor"], 3400, "Alice baseline must be captured")
    Assert.Equal(storage.rioBaselineByKey["Bob-Draenor"], 2800, "Bob baseline must be captured")
    Assert.Equal(storage.hasRioBaselineSnapshot, true, "has-snapshot flag must be true after capture")
    Assert.Equal(storage.rioDeltaDisplayEnabled, false, "delta display must still be disabled right after capture")
    Assert.Equal(db.rioBaseline["Alice-Draenor"], 3400, "DB baseline must mirror the runtime snapshot")
  end)

  test("factory_controllers: CaptureRioBaselineSnapshot falls back to GetUnitRio when roster info lacks rio", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    storage.roster = {
      player = { name = "Alice", realm = "Draenor" },
    }
    local c = BuildCtx(rs, BuildModulesStub(), {
      GetUnitRio = function(unit)
        if unit == "player" then
          return 3400
        end
      end,
    })
    WithGlobals({ IsiLiveDB = nil }, function()
      InitializeHelpers(c, addon)
      c.CaptureRioBaselineSnapshot()
    end)
    Assert.Equal(
      storage.rioBaselineByKey["Alice-Draenor"],
      3400,
      "GetUnitRio fallback must populate the baseline when info.rio is missing"
    )
  end)

  test("factory_controllers: CaptureRioBaselineSnapshot floors fractional rio values", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    storage.roster = {
      player = { name = "Alice", realm = "Draenor", rio = 3400.7 },
    }
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
      c.CaptureRioBaselineSnapshot()
    end)
    Assert.Equal(storage.rioBaselineByKey["Alice-Draenor"], 3400, "fractional rio must be floored")
  end)

  test("factory_controllers: EnableRioDeltaDisplay skips when no snapshot exists", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
      c.EnableRioDeltaDisplay()
    end)
    Assert.Equal(storage.rioDeltaDisplayEnabled, false, "without a snapshot the display must stay disabled")
  end)

  test("factory_controllers: EnableRioDeltaDisplay enables when snapshot is present", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    storage.hasRioBaselineSnapshot = true
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
      c.EnableRioDeltaDisplay()
    end)
    Assert.Equal(storage.rioDeltaDisplayEnabled, true, "snapshot present must enable the display")
  end)

  test("factory_controllers: GetRioDeltaForRosterInfo returns nil without baseline snapshot", function()
    local addon = Load()
    local rs = BuildRuntimeStateStub()
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    Assert.Nil(c.GetRioDeltaForRosterInfo({ name = "Alice", rio = 3500 }), "no baseline => nil delta")
  end)

  test("factory_controllers: GetRioDeltaForRosterInfo returns nil when delta display is disabled", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    storage.hasRioBaselineSnapshot = true
    storage.rioBaselineByKey = { ["Alice-Draenor"] = 3400 }
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    Assert.Nil(
      c.GetRioDeltaForRosterInfo({ name = "Alice", realm = "Draenor", rio = 3500 }),
      "display disabled => nil delta"
    )
  end)

  test("factory_controllers: GetRioDeltaForRosterInfo returns positive delta when rio grew", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    storage.hasRioBaselineSnapshot = true
    storage.rioDeltaDisplayEnabled = true
    storage.rioBaselineByKey = { ["Alice-Draenor"] = 3400 }
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    Assert.Equal(
      c.GetRioDeltaForRosterInfo({ name = "Alice", realm = "Draenor", rio = 3450 }),
      50,
      "positive delta must equal current - baseline"
    )
  end)

  test("factory_controllers: GetRioDeltaForRosterInfo clamps negative delta to zero", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    storage.hasRioBaselineSnapshot = true
    storage.rioDeltaDisplayEnabled = true
    storage.rioBaselineByKey = { ["Alice-Draenor"] = 3400 }
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    Assert.Equal(
      c.GetRioDeltaForRosterInfo({ name = "Alice", realm = "Draenor", rio = 3300 }),
      0,
      "RIO regressions must clamp to 0 (never render a negative delta per RULE-RIO-DELTA-FORMAT)"
    )
  end)

  test("factory_controllers: GetRioDeltaForRosterInfo prefers live GetUnitRio over info.rio", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    storage.hasRioBaselineSnapshot = true
    storage.rioDeltaDisplayEnabled = true
    storage.rioBaselineByKey = { ["Alice-Draenor"] = 3400 }
    local liveRioCalls = 0
    local c = BuildCtx(rs, BuildModulesStub(), {
      GetUnitRio = function(unit)
        liveRioCalls = liveRioCalls + 1
        if unit == "player" then
          return 3500
        end
      end,
    })
    local info = { name = "Alice", realm = "Draenor", rio = 3400 }
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    Assert.Equal(
      c.GetRioDeltaForRosterInfo(info, "player"),
      100,
      "live GetUnitRio (3500) must override info.rio (3400) for the delta computation"
    )
    Assert.Equal(liveRioCalls, 1, "GetUnitRio must be called exactly once per delta lookup with a unit token")
    Assert.Equal(info.rio, 3500, "info.rio must be mutated to the live value for downstream consumers")
  end)

  test("factory_controllers: GetRioDeltaForRosterInfo returns nil when no rio value is available", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    storage.hasRioBaselineSnapshot = true
    storage.rioDeltaDisplayEnabled = true
    storage.rioBaselineByKey = { ["Alice-Draenor"] = 3400 }
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    Assert.Nil(
      c.GetRioDeltaForRosterInfo({ name = "Alice", realm = "Draenor" }),
      "missing info.rio and no live fallback must resolve to nil"
    )
  end)

  test("factory_controllers: GetRioDeltaForRosterInfo returns nil when baseline has no entry for the key", function()
    local addon = Load()
    local rs, storage = BuildRuntimeStateStub()
    storage.hasRioBaselineSnapshot = true
    storage.rioDeltaDisplayEnabled = true
    storage.rioBaselineByKey = { ["Bob-Draenor"] = 2800 }
    local c = BuildCtx(rs, BuildModulesStub())
    WithGlobals({}, function()
      InitializeHelpers(c, addon)
    end)
    Assert.Nil(
      c.GetRioDeltaForRosterInfo({ name = "Alice", realm = "Draenor", rio = 3500 }),
      "missing baseline key must resolve to nil"
    )
  end)
end
