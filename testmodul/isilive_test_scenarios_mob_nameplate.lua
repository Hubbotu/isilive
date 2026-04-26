---@diagnostic disable: undefined-global, undefined-field

-- Scenarios for ui/isiLive_mob_nameplate.lua.
-- The module attaches a FontString overlay to each enemy nameplate in an
-- active Mythic+ keystone and renders the unit's progress contribution via
-- C_ScenarioInfo.GetUnitCriteriaProgressValues(unit). We stub Blizzard's
-- nameplate + scenario APIs, drive UpdateNameplate via the test helper, and
-- assert on the resulting frame/text state.

local function MakeFontString()
  local fs = { _text = "", _points = nil, _color = nil, _font = nil, _setFontCallCount = 0 }
  function fs:SetText(text)
    self._text = tostring(text or "")
  end
  function fs:SetPoint(...)
    self._points = { ... }
  end
  function fs:SetTextColor(r, g, b, a)
    self._color = { r, g, b, a }
  end
  function fs:SetFont(file, size, flags)
    self._font = { file = file, size = size, flags = flags }
    self._setFontCallCount = self._setFontCallCount + 1
  end
  function fs:GetText()
    return self._text
  end
  return fs
end

-- Stand-in for the global FontObject `GameFontNormalOutline` that ApplyFont
-- queries via `GetFont()` to inherit the template's font-file + flags.
-- Returns deterministic values so the SetFont assertions can compare exactly.
local function MakeGameFontNormalOutline()
  return {
    GetFont = function(_self)
      return "Fonts\\\\FRIZQT__.TTF", 10, "OUTLINE"
    end,
  }
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
    GameFontNormalOutline = overrides.GameFontNormalOutline or MakeGameFontNormalOutline(),
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

local function RegisterDefensivePathTests(test, Assert, WithGlobals, LoadAddonModules)
  local POSITIONS = { "LEFT", "RIGHT", "TOP", "BOTTOM" }
  local EXPECTED_ANCHORS = {
    LEFT = { "RIGHT", "LEFT" },
    RIGHT = { "LEFT", "RIGHT" },
    TOP = { "BOTTOM", "TOP" },
    BOTTOM = { "TOP", "BOTTOM" },
  }

  for _, pos in ipairs(POSITIONS) do
    test("MobNameplate ApplyPosition anchors correctly for position " .. pos, function()
      local globals = BuildEnv({
        units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
        nameplates = { nameplate1 = MakeFrame() },
        progressValues = { nameplate1 = { count = 5, total = 431, percent = "1.16" } },
      })
      WithGlobals(globals, function()
        local addon = LoadModule(LoadAddonModules)
        addon.MobNameplate.SetAppearance({ position = pos })
        addon.MobNameplate.SetEnabled(true)
        addon.MobNameplate._Test_UpdateNameplate("nameplate1")

        local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
        Assert.True(frame ~= nil, "frame must exist for pos=" .. pos)
        local expected = EXPECTED_ANCHORS[pos]
        Assert.Equal(frame._points[1], expected[1], "frame anchor point for pos=" .. pos)
        Assert.Equal(frame._points[3], expected[2], "nameplate anchor point for pos=" .. pos)
      end)
    end)
  end

  test("MobNameplate ApplyPosition falls back to CENTER for unknown position", function()
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 431, percent = "1.16" } },
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      addon.MobNameplate.SetAppearance({ position = "DIAGONAL" })
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      Assert.True(frame ~= nil, "frame must exist for unknown position")
      Assert.Equal(frame._points[1], "CENTER", "unknown position falls back to CENTER anchor")
      Assert.Equal(frame._points[3], "CENTER", "unknown position falls back to CENTER nameplate anchor")
    end)
  end)

  test("MobNameplate hides nothing and creates no frame when CreateFrame pcall throws", function()
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 431, percent = "1.16" } },
    })
    globals.CreateFrame = function()
      error("createframe blew up in test")
    end
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      -- SetEnabled tries to create the event frame via CreateFrame pcall.
      -- The module must swallow the failure and not crash the caller.
      addon.MobNameplate.SetEnabled(true)
      Assert.True(
        addon.MobNameplate._Test_GetFrames()["nameplate1"] == nil,
        "no frame should be created when CreateFrame pcall fails"
      )
    end)
  end)

  test("MobNameplate hides unit when UnitReaction returns a Secret Value", function()
    local secret = "__ISILIVE_TEST_SECRET_REACTION__"
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 431, percent = "1.16" } },
      UnitReaction = function()
        return secret
      end,
      issecretvalue = function(v)
        return v == secret
      end,
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      -- A Secret-Valued reaction must not taint the unit-eligibility check.
      -- The module should ignore reaction > 4 when reaction is secret, so
      -- rendering proceeds (reaction defaults to "hostile" when unreadable).
      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      Assert.True(frame ~= nil, "Secret-Valued reaction must not crash; unit treated as eligible")
    end)
  end)

  test("MobNameplate NAME_PLATE_UNIT_REMOVED OnEvent hides frame and clears pool entry", function()
    local globals, _, frames = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 431, percent = "1.16" } },
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")
      Assert.True(
        addon.MobNameplate._Test_GetFrames()["nameplate1"] ~= nil,
        "frame should exist before NAME_PLATE_UNIT_REMOVED"
      )

      -- Find the event frame (the one with scripts) and drive its OnEvent handler.
      local eventFrame = nil
      for _, f in ipairs(frames) do
        if f._scripts and type(f._scripts.OnEvent) == "function" then
          eventFrame = f
          break
        end
      end
      eventFrame = Assert.NotNil(eventFrame, "event frame with OnEvent script must exist")
      eventFrame._scripts.OnEvent(eventFrame, "NAME_PLATE_UNIT_REMOVED", "nameplate1")

      Assert.True(
        addon.MobNameplate._Test_GetFrames()["nameplate1"] == nil,
        "NAME_PLATE_UNIT_REMOVED must clear the pool entry for the removed unit"
      )
    end)
  end)

  test("MobNameplate SetFormat during enabled=true triggers RefreshAll", function()
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 431, percent = "1.16" } },
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")
      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      Assert.Equal(frame.text._text, "1.16%", "initial render uses default format")

      -- Flip showPercent off: RefreshAll should re-apply to all active frames and
      -- produce empty text, which hides the frame.
      addon.MobNameplate.SetFormat({ showPercent = false, bossTargetMode = "off" })
      Assert.True(frame._shown == false, "frame is hidden after SetFormat removes the only visible part")
    end)
  end)

  test("MobNameplate SetAppearance during enabled=true re-applies font size", function()
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 431, percent = "1.16" } },
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      addon.MobNameplate.SetAppearance({ fontSize = 19 })
      local state = addon.MobNameplate._Test_GetState()
      Assert.Equal(state.appearance.fontSize, 19, "fontSize must be persisted in module state")
    end)
  end)

  test("MobNameplate ResolveBossRemainder returns nil for mode off", function()
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
      addon.MobNameplate.SetFormat({ showPercent = true, bossTargetMode = "off" })
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      Assert.Equal(frame.text._text, "1.00%", "bossTargetMode=off appends no remainder, only percent")
    end)
  end)

  test("MobNameplate GetActiveChallengeMapID rejects Secret-Valued mapID", function()
    local secret = 999999
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 500, percent = "1.00" } },
      scenarioCriteria = {
        { totalQuantity = 1, quantity = 0, completed = false },
        { totalQuantity = 500, quantity = 85, completed = false },
      },
      C_ChallengeMode = {
        IsChallengeModeActive = function()
          return true
        end,
        GetActiveChallengeMapID = function()
          return secret
        end,
      },
      issecretvalue = function(v)
        return v == secret
      end,
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules, {
        MPlusBossTargets = {
          byMapID = { [secret] = { 28.07 } },
        },
      })
      addon.MobNameplate.SetFormat({ showPercent = true, bossTargetMode = "next" })
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      Assert.True(frame ~= nil and frame._shown == true, "frame renders the percent part")
      Assert.Equal(frame.text._text, "1.00%", "Secret-Valued mapID drops the bossTarget remainder")
    end)
  end)

  test("MobNameplate ResolveScenarioProgress ignores Secret-Valued numCriteria", function()
    local secret = 42
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 500, percent = "1.00" } },
      C_ScenarioInfo = {
        GetUnitCriteriaProgressValues = function()
          return 5, 500, "1.00"
        end,
        GetStepInfo = function()
          return { numCriteria = secret }
        end,
        GetCriteriaInfo = function()
          return nil
        end,
      },
      issecretvalue = function(v)
        return v == secret
      end,
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules, {
        MPlusBossTargets = {
          byMapID = { [161] = { 28.07 } },
        },
      })
      addon.MobNameplate.SetFormat({ showPercent = true, bossTargetMode = "next" })
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      Assert.Equal(frame.text._text, "1.00%", "Secret-Valued numCriteria drops bossTarget remainder safely")
    end)
  end)
end

local function RegisterFontSizeTests(test, Assert, WithGlobals, LoadAddonModules)
  test("MobNameplate ApplyFont calls SetFont with the configured fontSize on initial frame creation", function()
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 431, percent = "1.16" } },
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      addon.MobNameplate.SetAppearance({ fontSize = 22 })
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      frame = Assert.NotNil(frame, "frame must exist after update")
      local font = frame.text._font
      font = Assert.NotNil(font, "ApplyFont must call SetFont on the FontString")
      Assert.Equal(font.size, 22, "initial frame must use the configured fontSize, not the template default")
      Assert.True(font.file ~= nil and font.file ~= "", "SetFont must receive a non-empty font file path")
      Assert.True(
        type(font.flags) == "string" and font.flags ~= "",
        "SetFont must receive flags (e.g. OUTLINE) inherited from the template"
      )
    end)
  end)

  test("MobNameplate SetAppearance({fontSize}) during enabled re-applies SetFont with the new size", function()
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 431, percent = "1.16" } },
    })
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")
      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      frame = Assert.NotNil(frame, "frame must exist after first update")
      local initialCallCount = frame.text._setFontCallCount
      Assert.True(initialCallCount >= 1, "SetFont must have been called at least once during initial render")

      -- Slider moves to 19 mid-key; SetAppearance must trigger RefreshAll
      -- which re-runs UpdateNameplate -> ApplyFont with the new size.
      addon.MobNameplate.SetAppearance({ fontSize = 19 })
      Assert.True(
        frame.text._setFontCallCount > initialCallCount,
        "SetAppearance during enabled must trigger another SetFont call via RefreshAll"
      )
      Assert.Equal(frame.text._font.size, 19, "FontString must have the new fontSize after SetAppearance")
    end)
  end)

  test("MobNameplate ApplyFont falls back to default font when GameFontNormalOutline is missing", function()
    -- Simulates a runtime context where Blizzard has not (yet) registered the
    -- GameFontNormalOutline FontObject. ApplyFont must still call SetFont on
    -- the FontString with the configured size and a hardcoded fallback file
    -- so the nameplate label remains visible.
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 431, percent = "1.16" } },
    })
    globals.GameFontNormalOutline = nil
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      addon.MobNameplate.SetAppearance({ fontSize = 14 })
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      frame = Assert.NotNil(frame, "frame must still be created without the template global")
      local font = Assert.NotNil(frame.text._font, "ApplyFont must still call SetFont without template")
      Assert.Equal(font.size, 14, "configured fontSize must still be honored")
      Assert.True(font.file ~= nil and font.file ~= "", "fallback font file must be non-empty")
      Assert.Equal(font.flags, "OUTLINE", "fallback flags default to OUTLINE")
    end)
  end)

  test("MobNameplate font-size pipeline is unaffected by Plater being loaded", function()
    -- Plater/Platynator soft-detect lives in the settings UI, NOT in the
    -- nameplate module itself. The module renders identically regardless of
    -- which external nameplate addon is loaded; this scenario locks that in
    -- so a future "skip if Plater" optimisation cannot silently break the
    -- font-size pipeline.
    local globals = BuildEnv({
      units = { nameplate1 = { guid = "Creature-0-3889-161-12345-76132-0", reaction = 2 } },
      nameplates = { nameplate1 = MakeFrame() },
      progressValues = { nameplate1 = { count = 5, total = 431, percent = "1.16" } },
    })
    globals.IsAddOnLoaded = function(name)
      return name == "Plater"
    end
    globals.C_AddOns = {
      IsAddOnLoaded = function(name)
        return name == "Plater"
      end,
    }
    WithGlobals(globals, function()
      local addon = LoadModule(LoadAddonModules)
      addon.MobNameplate.SetAppearance({ fontSize = 16 })
      addon.MobNameplate.SetEnabled(true)
      addon.MobNameplate._Test_UpdateNameplate("nameplate1")

      local frame = addon.MobNameplate._Test_GetFrames()["nameplate1"]
      frame = Assert.NotNil(frame, "frame must still be created when Plater is loaded -- module ignores soft-detect")
      Assert.True(frame._shown == true, "overlay must render even with Plater loaded (user opt-in)")
      local font = Assert.NotNil(frame.text._font, "SetFont must still be called when Plater is loaded")
      Assert.Equal(font.size, 16, "fontSize must still be honoured when Plater is loaded")
    end)
  end)
end

return function(test, ctx)
  local Assert = ctx.assert
  local WithGlobals = ctx.with_globals
  local LoadAddonModules = ctx.load_modules

  RegisterLifecycleTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterRenderTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterDefensivePathTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterFontSizeTests(test, Assert, WithGlobals, LoadAddonModules)
end
