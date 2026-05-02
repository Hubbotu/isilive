-- Branch-coverage scenarios for ui/isiLive_ui.lua. Targets functions and code
-- paths that the existing isilive_test_scenarios_ui.lua does not exercise:
--   * UI.CreateMainFrame end-to-end (drag-handle, lock button, drag storm)
--   * Visibility controller combat-defer + raid-suppress branches
--   * Height/Width controllers' pending-during-combat fallback
--   * SavePosition writes IsiLiveDB.position after a drag stops
-- Keeps mocks intentionally minimal — every Frame method that ui.lua actually
-- calls is stubbed; everything else is left undefined so a future regression
-- that needs an unmocked API surfaces here as a clear test failure.

local function CreateTextureStub()
  return {
    SetAllPoints = function() end,
    SetColorTexture = function() end,
    SetTexture = function() end,
    SetSize = function() end,
    SetWidth = function() end,
    SetHeight = function() end,
    SetPoint = function() end,
    SetTexCoord = function() end,
    SetBlendMode = function() end,
    SetVertexColor = function() end,
    SetRotation = function() end,
    SetDrawLayer = function() end,
    Hide = function() end,
    Show = function() end,
  }
end

local function CreateFontStringStub()
  local fs = { _text = "", _shown = true }
  function fs:SetPoint(...)
    self._point = { ... }
  end
  function fs:SetJustifyH() end
  function fs:SetJustifyV() end
  function fs:SetTextColor() end
  function fs:SetText(value)
    self._text = tostring(value or "")
  end
  function fs:GetText()
    return self._text
  end
  function fs:SetWidth() end
  function fs:SetWordWrap() end
  function fs:SetNonSpaceWrap() end
  function fs:GetFont()
    return "Fonts\\FRIZQT__.TTF", 12, ""
  end
  function fs:SetFont() end
  function fs:GetStringHeight()
    return 14
  end
  function fs:Hide()
    self._shown = false
  end
  function fs:Show()
    self._shown = true
  end
  return fs
end

local function CreateFrameStub(_frameType, _name, parent, _template)
  local frame = {
    _scripts = {},
    _shown = false,
    _movable = false,
    _mouseEnabled = false,
    _draggable = false,
    _attrs = {},
    _frameStrata = "MEDIUM",
    _frameLevel = 1,
    _width = 100,
    _height = 100,
    _alpha = 1,
    _moving = false,
    _stopMovingCalls = 0,
    _parent = parent,
  }
  function frame:SetSize(w, h)
    self._width = w
    self._height = h
  end
  function frame:SetWidth(w)
    self._width = w
  end
  function frame:SetHeight(h)
    self._height = h
  end
  function frame:GetWidth()
    return self._width
  end
  function frame:GetHeight()
    return self._height
  end
  function frame:SetPoint(point, relativeTo, relativePoint, x, y)
    self._point = { point, relativeTo, relativePoint, x or 0, y or 0 }
  end
  function frame:GetPoint()
    if not self._point then
      return nil
    end
    return self._point[1], self._point[2], self._point[3], self._point[4], self._point[5]
  end
  function frame:ClearAllPoints()
    self._point = nil
  end
  function frame:SetFrameStrata(s)
    self._frameStrata = s
  end
  function frame:GetFrameStrata()
    return self._frameStrata
  end
  function frame:SetFrameLevel(level)
    self._frameLevel = level
  end
  function frame:GetFrameLevel()
    return self._frameLevel or 1
  end
  function frame:SetMovable(flag)
    self._movable = flag == true
  end
  function frame:IsMovable()
    return self._movable
  end
  function frame:EnableMouse(flag)
    self._mouseEnabled = flag == true
  end
  function frame:RegisterForDrag()
    self._draggable = true
  end
  function frame:UnregisterForDrag()
    self._draggable = false
  end
  function frame:RegisterForClicks() end
  function frame:RegisterEvent(event)
    self._events = self._events or {}
    self._events[event] = true
  end
  function frame:UnregisterEvent(event)
    if self._events then
      self._events[event] = nil
    end
  end
  function frame:UnregisterAllEvents()
    self._events = {}
  end
  function frame:Show()
    self._shown = true
  end
  function frame:Hide()
    self._shown = false
  end
  function frame:IsShown()
    return self._shown == true
  end
  function frame:SetScript(name, fn)
    self._scripts[name] = fn
  end
  function frame:GetScript(name)
    return self._scripts[name]
  end
  function frame:HookScript(name, fn)
    -- Append as additional handler; tests only need the LATEST registration.
    self._scripts[name] = fn
  end
  function frame:StartMoving()
    self._moving = true
  end
  function frame:StopMovingOrSizing()
    self._moving = false
    self._stopMovingCalls = self._stopMovingCalls + 1
  end
  function frame:SetAlpha(a)
    self._alpha = a
  end
  function frame:GetAlpha()
    return self._alpha
  end
  function frame:SetClampedToScreen() end
  function frame:SetIgnoreParentAlpha() end
  function frame:SetBackdrop() end
  function frame:SetBackdropColor() end
  function frame:SetBackdropBorderColor() end
  function frame:SetAttribute(key, value)
    self._attrs[key] = value
  end
  function frame:CreateTexture()
    return CreateTextureStub()
  end
  function frame:CreateFontString()
    return CreateFontStringStub()
  end
  return frame
end

local function RequireValue(value, message)
  if value == nil then
    error(message, 2)
  end
  return value
end

local function BuildMainFrameContext(opts)
  opts = opts or {}
  local inCombat = opts.inCombat == true
  local raidGroup = opts.raidGroup == true
  local dragLocked = opts.dragLocked == true

  return {
    UIParent = CreateFrameStub("Frame"),
    CreateFrame = CreateFrameStub,
    InCombatLockdown = function()
      return inCombat
    end,
    GameTooltip = {
      SetOwner = function() end,
      AddLine = function() end,
      Show = function() end,
      Hide = function() end,
    },
    setInCombat = function(flag)
      inCombat = flag == true
    end,
    setRaidGroup = function(flag)
      raidGroup = flag == true
    end,
    isInCombat = function()
      return inCombat
    end,
    isRaidGroup = function()
      return raidGroup
    end,
    isDragLocked = function()
      return dragLocked
    end,
    setDragLocked = function(flag)
      dragLocked = flag == true
    end,
  }
end

local function CreateMainFrame(addon, ctx, callbacks)
  callbacks = callbacks or {}
  return addon.UI.CreateMainFrame({
    parent = ctx.UIParent,
    isInCombat = ctx.isInCombat,
    isRaidGroup = ctx.isRaidGroup,
    isDragLocked = ctx.isDragLocked,
    onShownInGroup = callbacks.onShownInGroup or function() end,
    onShownNoGroup = callbacks.onShownNoGroup or function() end,
  })
end

local function RegisterCreateMainFrameTests(test, Assert, WithGlobals, LoadAddonModules)
  test("UI.CreateMainFrame returns a controller with the expected api", function()
    local ctx = BuildMainFrameContext()
    WithGlobals(ctx, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_ui.lua" })
      local mainFrame = CreateMainFrame(addon, ctx)

      Assert.NotNil(mainFrame, "CreateMainFrame must return a controller table")
      Assert.NotNil(mainFrame.frame, "controller exposes .frame")
      Assert.True(type(mainFrame.SetVisible) == "function", "controller exposes SetVisible")
      Assert.True(type(mainFrame.ToggleVisibility) == "function", "controller exposes ToggleVisibility")
      Assert.True(type(mainFrame.SetDragLocked) == "function", "controller exposes SetDragLocked")
      Assert.False(mainFrame.frame:IsShown(), "main frame starts hidden")
    end)
  end)

  test("MainFrame.SetVisible(true) while in raid is suppressed", function()
    local ctx = BuildMainFrameContext({ raidGroup = true })
    WithGlobals(ctx, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_ui.lua" })
      local mainFrame = CreateMainFrame(addon, ctx)

      mainFrame.SetVisible(true)
      Assert.False(mainFrame.frame:IsShown(), "raid group must keep main frame hidden even when SetVisible(true)")
    end)
  end)

  test("MainFrame.SetVisible(true) while in combat defers to pendingVisible", function()
    local ctx = BuildMainFrameContext({ inCombat = true })
    WithGlobals(ctx, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_ui.lua" })
      local mainFrame = CreateMainFrame(addon, ctx)

      mainFrame.SetVisible(true)
      Assert.False(mainFrame.frame:IsShown(), "combat-active SetVisible(true) does not show the frame immediately")
      Assert.Equal(mainFrame.GetPendingVisible(), true, "combat-active SetVisible(true) records pending=true")

      -- Leaving combat and replaying SetVisible(true) clears pending and shows.
      ctx.setInCombat(false)
      mainFrame.SetVisible(true)
      Assert.True(mainFrame.frame:IsShown(), "out-of-combat SetVisible(true) shows the frame")
      Assert.Nil(mainFrame.GetPendingVisible(), "applied SetVisible clears pending state")
    end)
  end)

  test("MainFrame.ToggleVisibility while in combat captures the inverse pending state", function()
    local ctx = BuildMainFrameContext({ inCombat = false })
    WithGlobals(ctx, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_ui.lua" })
      local mainFrame = CreateMainFrame(addon, ctx)

      -- show first (out of combat)
      mainFrame.SetVisible(true)
      Assert.True(mainFrame.frame:IsShown(), "frame visible after out-of-combat SetVisible(true)")

      -- enter combat, then toggle: pending=false
      ctx.setInCombat(true)
      mainFrame.ToggleVisibility(false)
      Assert.True(mainFrame.frame:IsShown(), "ToggleVisibility in combat does not flip the frame immediately")
      Assert.Equal(mainFrame.GetPendingVisible(), false, "ToggleVisibility in combat records pending=false (inverse)")
    end)
  end)

  test("MainFrame.ToggleVisibility while in raid hides any visible frame", function()
    local ctx = BuildMainFrameContext()
    WithGlobals(ctx, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_ui.lua" })
      local mainFrame = CreateMainFrame(addon, ctx)

      mainFrame.SetVisible(true)
      Assert.True(mainFrame.frame:IsShown(), "frame visible before raid transition")

      ctx.setRaidGroup(true)
      mainFrame.ToggleVisibility(true)
      Assert.False(mainFrame.frame:IsShown(), "ToggleVisibility in raid hides the visible frame")
    end)
  end)

  test("MainFrame.SetHeightSafe / SetWidthSafe defer when in combat", function()
    local ctx = BuildMainFrameContext({ inCombat = true })
    WithGlobals(ctx, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_ui.lua" })
      local mainFrame = CreateMainFrame(addon, ctx)
      local startWidth = mainFrame.frame:GetWidth()
      local startHeight = mainFrame.frame:GetHeight()

      mainFrame.SetHeightSafe(444)
      mainFrame.SetWidthSafe(888)

      Assert.Equal(mainFrame.frame:GetHeight(), startHeight, "combat blocks immediate height change")
      Assert.Equal(mainFrame.frame:GetWidth(), startWidth, "combat blocks immediate width change")
      Assert.Equal(mainFrame.GetPendingHeight(), 444, "pending height matches requested value")
      Assert.Equal(mainFrame.GetPendingWidth(), 888, "pending width matches requested value")

      ctx.setInCombat(false)
      mainFrame.SetHeightSafe(333)
      mainFrame.SetWidthSafe(777)
      Assert.Equal(mainFrame.frame:GetHeight(), 333, "out-of-combat SetHeightSafe applies immediately")
      Assert.Equal(mainFrame.frame:GetWidth(), 777, "out-of-combat SetWidthSafe applies immediately")
      Assert.Nil(mainFrame.GetPendingHeight(), "applied SetHeightSafe clears pending height")
      Assert.Nil(mainFrame.GetPendingWidth(), "applied SetWidthSafe clears pending width")
    end)
  end)

  test("MainFrame drag storm: OnDragStop persists position via SavePosition", function()
    local ctx = BuildMainFrameContext({ dragLocked = false })
    -- IsiLiveDB starts as nil so SavePosition has to allocate a fresh table.
    ctx.IsiLiveDB = nil
    WithGlobals(ctx, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_ui.lua" })
      local mainFrame = CreateMainFrame(addon, ctx)
      mainFrame.SetDragLocked(false)

      local onDragStart = mainFrame.frame:GetScript("OnDragStart")
      local onDragStop = mainFrame.frame:GetScript("OnDragStop")
      onDragStart = RequireValue(onDragStart, "main frame must register OnDragStart")
      onDragStop = RequireValue(onDragStop, "main frame must register OnDragStop")

      onDragStart(mainFrame.frame)
      Assert.True(mainFrame.frame._moving == true, "OnDragStart starts moving while unlocked")

      -- Move the frame to a different anchor so SavePosition records new coords.
      mainFrame.frame:ClearAllPoints()
      mainFrame.frame:SetPoint("TOPRIGHT", ctx.UIParent, "TOPRIGHT", 17, -8)

      onDragStop(mainFrame.frame)
      Assert.False(mainFrame.frame._moving == true, "OnDragStop ends move state")
      Assert.True(mainFrame.frame._stopMovingCalls >= 1, "StopMovingOrSizing was actually invoked")

      local db = rawget(_G, "IsiLiveDB")
      Assert.NotNil(db, "SavePosition allocates IsiLiveDB if missing")
      Assert.NotNil(db.position, "SavePosition writes IsiLiveDB.position")
      Assert.Equal(db.position.point, "TOPRIGHT", "saved point matches frame point")
      Assert.Equal(db.position.x, 17, "saved x offset matches frame point")
      Assert.Equal(db.position.y, -8, "saved y offset matches frame point")
    end)
  end)

  test("MainFrame OnDragStart while locked is a no-op", function()
    local ctx = BuildMainFrameContext({ dragLocked = true })
    WithGlobals(ctx, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_ui.lua" })
      local mainFrame = CreateMainFrame(addon, ctx)

      local onDragStart = mainFrame.frame:GetScript("OnDragStart")
      onDragStart = RequireValue(onDragStart, "main frame must register OnDragStart")

      onDragStart(mainFrame.frame)
      Assert.False(mainFrame.frame._moving == true, "locked drag must not start moving")
    end)
  end)

  test("MainFrame.SetDragLocked(true) during an active drag finalizes the position", function()
    local ctx = BuildMainFrameContext({ dragLocked = false })
    WithGlobals(ctx, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_ui.lua" })
      local mainFrame = CreateMainFrame(addon, ctx)

      mainFrame.SetDragLocked(false)
      local onDragStart = mainFrame.frame:GetScript("OnDragStart")
      onDragStart(mainFrame.frame)
      Assert.True(mainFrame.frame._moving == true, "drag is active before lock")

      mainFrame.frame:ClearAllPoints()
      mainFrame.frame:SetPoint("BOTTOMLEFT", ctx.UIParent, "BOTTOMLEFT", 5, 5)

      mainFrame.SetDragLocked(true)
      Assert.False(mainFrame.frame._moving == true, "locking mid-drag stops the drag")
      Assert.True(
        mainFrame.frame._stopMovingCalls >= 1,
        "StopMovingOrSizing fires once the lock is applied during an active drag"
      )

      local db = rawget(_G, "IsiLiveDB")
      Assert.NotNil(db, "lock-during-drag still triggers SavePosition")
      Assert.Equal(db.position.point, "BOTTOMLEFT", "saved point reflects the in-flight drag location")
    end)
  end)
end

return function(test, ctx)
  local Assert = RequireValue(ctx.assert, "ui_branches scenario ctx.assert should exist")
  local WithGlobals = RequireValue(ctx.with_globals, "ui_branches scenario ctx.with_globals should exist")
  local LoadAddonModules = RequireValue(ctx.load_modules, "ui_branches scenario ctx.load_modules should exist")

  RegisterCreateMainFrameTests(test, Assert, WithGlobals, LoadAddonModules)
end
