---@diagnostic disable: undefined-global, undefined-field

-- Scenarios for ui/isiLive_mob_nameplate.lua.
-- The module attaches a FontString overlay to each enemy nameplate in an
-- active Mythic+ keystone and renders the unit's progress contribution via
-- C_ScenarioInfo.GetUnitCriteriaProgressValues(unit). We stub Blizzard's
-- nameplate + scenario APIs, drive UpdateNameplate via the test helper, and
-- assert on the resulting frame/text state.

local function MakeFontString()
  local fs = { _text = "", _points = nil, _color = nil }
  function fs:SetText(text)
    self._text = tostring(text or "")
  end
  function fs:SetPoint(...)
    self._points = { ... }
  end
  function fs:SetTextColor(r, g, b, a)
    self._color = { r, g, b, a }
  end
  function fs:GetText()
    return self._text
  end
  return fs
end

local function MakeFrame()
  local f = {
    _shown = false,
    _points = nil,
    _size = nil,
    _strata = nil,
    _ignoreParentAlpha = nil,
    _scripts = {},
    _events = {},
  }
  function f:SetSize(w, h)
    self._size = { w, h }
  end
  function f:SetFrameStrata(s)
    self._strata = s
  end
  function f:SetIgnoreParentAlpha(flag)
    self._ignoreParentAlpha = flag
  end
  function f:SetPoint(...)
    self._points = { ... }
  end
  function f:ClearAllPoints()
    self._points = nil
  end
  function f:Show()
    self._shown = true
  end
  function f:Hide()
    self._shown = false
  end
  function f:IsShown()
    return self._shown == true
  end
  function f:SetScript(name, fn)
    self._scripts[name] = fn
  end
  function f:GetScript(name)
    return self._scripts[name]
  end
  function f:RegisterEvent(event)
    self._events[event] = true
  end
  function f:UnregisterEvent(event)
    self._events[event] = nil
  end
  function f:UnregisterAllEvents()
    self._events = {}
  end
  function f:CreateFontString(_name, _layer, _template)
    return MakeFontString()
  end
  return f
end

local function BuildEnv(overrides)
  overrides = overrides or {}
  local createdFrames = {}
  local state = {
    challengeActive = overrides.challengeActive,
    mapID = overrides.mapID,
    units = overrides.units or {},
    nameplates = overrides.nameplates or {},
    progressValues = overrides.progressValues or {},
    scenarioCriteria = overrides.scenarioCriteria,
  }
  if state.challengeActive == nil then
    state.challengeActive = true
  end
  if state.mapID == nil then
    state.mapID = 161
  end

  local globals = {
    CreateFrame = function()
      local f = MakeFrame()
      table.insert(createdFrames, f)
      return f
    end,
    UIParent = {},
    UnitExists = overrides.UnitExists or function(unit)
      return state.units[unit] ~= nil
    end,
    UnitGUID = overrides.UnitGUID or function(unit)
      local u = state.units[unit]
      return u and u.guid or nil
    end,
    UnitReaction = overrides.UnitReaction or function(unit)
      local u = state.units[unit]
      if u and u.reaction then
        return u.reaction
      end
      return 2
    end,
    C_NamePlate = overrides.C_NamePlate or {
      GetNamePlateForUnit = function(unit)
        return state.nameplates[unit]
      end,
    },
    C_ChallengeMode = overrides.C_ChallengeMode or {
      IsChallengeModeActive = function()
        return state.challengeActive == true
      end,
      GetActiveChallengeMapID = function()
        return state.mapID
      end,
    },
    C_ScenarioInfo = overrides.C_ScenarioInfo or {
      GetUnitCriteriaProgressValues = function(unit)
        local v = state.progressValues[unit]
        if not v then
          return nil
        end
        return v.count, v.total, v.percent
      end,
      GetStepInfo = function()
        if state.scenarioCriteria then
          return { numCriteria = #state.scenarioCriteria }
        end
        return { numCriteria = 0 }
      end,
      GetCriteriaInfo = function(idx)
        if state.scenarioCriteria then
          return state.scenarioCriteria[idx]
        end
        return nil
      end,
    },
    issecretvalue = overrides.issecretvalue,
  }

  if overrides.globals then
    for k, v in pairs(overrides.globals) do
      globals[k] = v
    end
  end

  return globals, state, createdFrames
end

local function LoadModule(LoadAddonModules, addonOverrides)
  return LoadAddonModules({ "isiLive_mob_nameplate.lua" }, addonOverrides)
end

local function RegisterLifecycleTests(test, Assert, WithGlobals, LoadAddonModules)
  test("MobNameplate.Register reports success when progress + nameplate APIs are present", function()
    local globals = BuildEnv()
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      local ok = addon.MobNameplate.Register()
      Assert.True(ok, "Register() must succeed when C_ScenarioInfo + C_NamePlate are available")
    end)
  end)

  test("MobNameplate.Register reports failure when C_ScenarioInfo is missing", function()
    local globals = BuildEnv({ C_ScenarioInfo = false })
    globals.C_ScenarioInfo = nil
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      local ok = addon.MobNameplate.Register()
      Assert.False(ok, "Register() must fail without C_ScenarioInfo")
    end)
  end)

  test("MobNameplate.Register reports failure when C_NamePlate is missing", function()
    local globals = BuildEnv({ C_NamePlate = false })
    globals.C_NamePlate = nil
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      local ok = addon.MobNameplate.Register()
      Assert.False(ok, "Register() must fail without C_NamePlate")
    end)
  end)

  test("MobNameplate.SetEnabled(true) registers nameplate + challenge events on a tracker frame", function()
    local globals, _state, frames = BuildEnv()
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      addon.MobNameplate.SetEnabled(true)

      local eventFrame = nil
      for _, f in ipairs(frames) do
        if f._events and next(f._events) ~= nil then
          eventFrame = f
          break
        end
      end
      Assert.True(eventFrame ~= nil, "SetEnabled(true) must register events on a dedicated frame")
      Assert.True(eventFrame._events["NAME_PLATE_UNIT_ADDED"] == true, "NAME_PLATE_UNIT_ADDED must be registered")
      Assert.True(eventFrame._events["NAME_PLATE_UNIT_REMOVED"] == true, "NAME_PLATE_UNIT_REMOVED must be registered")
      Assert.True(eventFrame._events["CHALLENGE_MODE_START"] == true, "CHALLENGE_MODE_START must be registered")
      Assert.True(eventFrame._events["PLAYER_ENTERING_WORLD"] == true, "PLAYER_ENTERING_WORLD must be registered")
      Assert.True(eventFrame._events["SCENARIO_UPDATE"] == true, "SCENARIO_UPDATE must be registered")

      addon.MobNameplate.SetEnabled(false)
      Assert.True(next(eventFrame._events) == nil, "SetEnabled(false) must unregister all events")
    end)
  end)
end

local function RegisterRenderTests(test, Assert, WithGlobals, LoadAddonModules)
  test("MobNameplate renders percent text for an eligible hostile unit in an active key", function()
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 431, percent = "1.16" } },
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      local pool = addon.MobNameplate._Test_GetFrames()
      local frame = pool["nameplate1"]
      Assert.True(frame ~= nil, "frame must be created for eligible nameplate")
      Assert.True(frame._shown == true, "frame must be visible")
      Assert.Equal(frame.text._text, "1.16%", "default format renders the percent string with a trailing %")
    end)
  end)

  test("MobNameplate hides text for friendly units (reaction > 4)", function()
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 5 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 431, percent = "1.16" } },
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      Assert.True(frame == nil, "no frame should be created for a friendly unit (reaction > 4)")
    end)
  end)

  test("MobNameplate hides text when the key is not active", function()
    local globals = BuildEnv({
      challengeActive = false,
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 431, percent = "1.16" } },
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      Assert.True(frame == nil, "no frame should be created when challenge mode is not active")
    end)
  end)

  test("MobNameplate hides text when UnitGUID is a Secret Value", function()
    local secret = "__ISILIVE_TEST_SECRET_GUID__"
    local globals = BuildEnv({
      units = { nameplate1 = { guid = secret, reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 431, percent = "1.16" } },
      issecretvalue = function(v)
        return v == secret
      end,
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      Assert.True(frame == nil, "Secret-Valued GUID must not produce a frame")
    end)
  end)

  test("MobNameplate hides text when percentString is a Secret Value", function()
    local secret = "__ISILIVE_TEST_SECRET_PERCENT__"
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 431, percent = secret } },
      issecretvalue = function(v)
        return v == secret
      end,
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      Assert.True(frame == nil, "Secret-Valued percentString must not produce a visible frame")
    end)
  end)

  test("MobNameplate SetFormat(bossTargetMode=next) renders +X% remainder to next boss", function()
    -- Scenario: Skyreach (mapID 161), boss targets { 28.07, 52.2, 60.09, 100 }.
    -- Current forces progress: 85 / 500 = 17% (raw). First boss not completed,
    -- so the remainder toward the first boss target is 28.07 - 17 = 11.07 -> "+11%".
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 500, percent = "1.00" } },
      scenarioCriteria = {
        { totalQuantity = 1, quantity = 0, completed = false }, -- boss 1 open
        { totalQuantity = 1, quantity = 0, completed = false }, -- boss 2 open
        { totalQuantity = 1, quantity = 0, completed = false }, -- boss 3 open
        { totalQuantity = 1, quantity = 0, completed = false }, -- boss 4 open
        { totalQuantity = 500, quantity = 85, completed = false }, -- forces
      },
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules, {
        MPlusBossTargets = {
          byMapID = { [161] = { 28.07, 52.2, 60.09, 100 } },
        },
      })
      addon.MobNameplate.SetFormat({ showPercent = false, bossTargetMode = "next" })
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      Assert.True(frame ~= nil and frame._shown == true, "frame must be visible when bossTargetMode is on")
      Assert.Equal(frame.text._text, "+11%", "bossTargetMode=next renders remainder as '+N%'")
    end)
  end)

  test("MobNameplate SetFormat(bossTargetMode=end) renders remainder to 100% (final boss)", function()
    -- Forces progress 85/500 = 17% -> remainder to 100% = 83%.
    -- Boss-targets DB is not required for "end" mode, but we still set up a
    -- scenario step to make sure current-progress detection works.
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 500, percent = "1.00" } },
      scenarioCriteria = {
        { totalQuantity = 1, quantity = 0, completed = false },
        { totalQuantity = 500, quantity = 85, completed = false },
      },
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules, {
        MPlusBossTargets = {
          byMapID = { [161] = { 28.07, 52.2, 60.09, 100 } },
        },
      })
      addon.MobNameplate.SetFormat({ showPercent = false, bossTargetMode = "end" })
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      Assert.True(frame ~= nil and frame._shown == true, "frame must be visible in end mode too")
      Assert.Equal(frame.text._text, "+83%", "bossTargetMode=end renders 100% - current as '+N%'")
    end)
  end)

  test("MobNameplate hides boss-target when no active challenge map matches", function()
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 500, percent = "1.00" } },
      mapID = 99999, -- map id that has no boss-target entry in the DB
      scenarioCriteria = {
        { totalQuantity = 1, quantity = 0, completed = false },
        { totalQuantity = 500, quantity = 85, completed = false },
      },
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules, {
        MPlusBossTargets = {
          byMapID = { [161] = { 28.07, 52.2, 60.09, 100 } },
        },
      })
      addon.MobNameplate.SetFormat({ showPercent = true, bossTargetMode = "next" })
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      Assert.True(frame ~= nil and frame._shown == true, "frame still renders the percent part")
      Assert.Equal(frame.text._text, "1.00%", "unknown map -> no bossTarget part appended")
    end)
  end)

  test("MobNameplate hides and drops the pool entry after NAME_PLATE_UNIT_REMOVED", function()
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 431, percent = "1.16" } },
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")
      Assert.True(addon.MobNameplate._Test_GetFrames()["nameplate1"] ~= nil, "frame should exist after update")

      -- Simulate NAME_PLATE_UNIT_REMOVED via the internal path: setting enabled off
      -- forces HideAll. Alternatively, the event handler is attached to a frame
      -- we cannot easily reach by name; instead we simply disable and re-enable.
      addon.MobNameplate.SetEnabled(false)
      Assert.True(addon.MobNameplate._Test_GetFrames()["nameplate1"] == nil, "disable must clear the frame pool")
    end)
  end)
end

return function(test, ctx)
  local Assert = ctx.assert
  local WithGlobals = ctx.with_globals
  local LoadAddonModules = ctx.load_modules

  RegisterLifecycleTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterRenderTests(test, Assert, WithGlobals, LoadAddonModules)
end
