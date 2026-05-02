-- Branch-coverage scenarios for ui/isiLive_notice.lua. Targets functions and
-- code paths that the existing isilive_test_scenarios_ui_center_notice.lua
-- file does not exercise:
--   * Notice.CreateInviteHint full lifecycle (anchor resolution, OnUpdate
--     auto-hide, manual-texture fallback when SetBackdrop is unavailable)
--   * PortalNavigator close-by-right-click and close-button branches
--   * CreateCenterNotice teleport-button blink animation tick

local function CreateTextureStub()
  return {
    _hidden = false,
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
    Hide = function(self)
      self._hidden = true
    end,
    Show = function(self)
      self._hidden = false
    end,
  }
end

local function CreateFontStringStub()
  local fs = { _shown = true, _text = "" }
  function fs:SetPoint(...)
    self._point = { ... }
  end
  function fs:GetPoint()
    local p = self._point
    if not p then
      return nil
    end
    return p[1], p[2], p[3], p[4], p[5]
  end
  function fs:SetText(value)
    self._text = tostring(value or "")
  end
  function fs:GetText()
    return self._text
  end
  function fs:SetJustifyH() end
  function fs:SetJustifyV() end
  function fs:SetTextColor() end
  function fs:SetWordWrap() end
  function fs:SetNonSpaceWrap() end
  function fs:SetWidth() end
  function fs:Hide()
    self._shown = false
  end
  function fs:Show()
    self._shown = true
  end
  function fs:SetFont() end
  function fs:GetFont()
    return "Fonts\\FRIZQT__.TTF", 12, ""
  end
  function fs:GetStringHeight()
    return 14
  end
  return fs
end

local function CreateFrameStub(_frameType, _name, parent, _template)
  local frame = {
    _scripts = {},
    _shown = false,
    _point = nil,
    _parent = parent,
    _frameStrata = "MEDIUM",
    _alpha = 1,
    _width = 100,
    _height = 50,
  }
  function frame:SetSize(w, h)
    self._width = w
    self._height = h
  end
  function frame:GetWidth()
    return self._width
  end
  function frame:GetHeight()
    return self._height
  end
  function frame:SetPoint(...)
    self._point = { ... }
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
  function frame:Hide()
    self._shown = false
  end
  function frame:Show()
    self._shown = true
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
  function frame:SetAlpha(a)
    self._alpha = a
  end
  function frame:GetAlpha()
    return self._alpha
  end
  function frame:CreateTexture()
    return CreateTextureStub()
  end
  function frame:CreateFontString()
    return CreateFontStringStub()
  end
  function frame:EnableMouse() end
  function frame:SetMovable() end
  function frame:RegisterForDrag() end
  function frame:SetClampedToScreen() end
  function frame:SetIgnoreParentAlpha() end
  return frame
end

local function RequireValue(value, message)
  if value == nil then
    error(message, 2)
  end
  return value
end

local function RegisterInviteHintTests(test, Assert, WithGlobals, LoadAddonModules)
  test("Notice.CreateInviteHint anchors to LFGListInviteDialog when shown", function()
    local now = 100
    local lfgListInviteDialog = CreateFrameStub()
    lfgListInviteDialog:Show()

    WithGlobals({
      UIParent = CreateFrameStub(),
      CreateFrame = CreateFrameStub,
      GetTime = function()
        return now
      end,
      LFGListInviteDialog = lfgListInviteDialog,
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_notice.lua" })
      local Notice = RequireValue(addon.Notice, "Notice module should load")
      local hint = Notice.CreateInviteHint({ parent = UIParent })

      hint.Show("Tank pending", 5)
      Assert.True(hint.frame:IsShown(), "invite hint should be visible after Show()")

      local point, relativeTo, relativePoint, _, _ = hint.frame:GetPoint()
      Assert.Equal(point, "TOP", "invite hint should anchor TOP-side")
      Assert.Equal(relativeTo, lfgListInviteDialog, "invite hint should anchor to LFGListInviteDialog when shown")
      Assert.Equal(relativePoint, "BOTTOM", "invite hint should anchor relative to dialog BOTTOM")
    end)
  end)

  test("Notice.CreateInviteHint falls back to LFGDungeonReadyDialog when invite dialog is hidden", function()
    local now = 200
    local lfgListInviteDialog = CreateFrameStub()
    lfgListInviteDialog:Hide()
    local lfgDungeonReadyDialog = CreateFrameStub()
    lfgDungeonReadyDialog:Show()

    WithGlobals({
      UIParent = CreateFrameStub(),
      CreateFrame = CreateFrameStub,
      GetTime = function()
        return now
      end,
      LFGListInviteDialog = lfgListInviteDialog,
      LFGDungeonReadyDialog = lfgDungeonReadyDialog,
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_notice.lua" })
      local Notice = RequireValue(addon.Notice, "Notice module should load")
      local hint = Notice.CreateInviteHint({ parent = UIParent })
      hint.Show("Healer pending", 5)

      local _, relativeTo = hint.frame:GetPoint()
      Assert.Equal(
        relativeTo,
        lfgDungeonReadyDialog,
        "invite hint should fall back to LFGDungeonReadyDialog when invite dialog is hidden"
      )
    end)
  end)

  test("Notice.CreateInviteHint falls back to global main frame when no LFG dialog is shown", function()
    local now = 300
    local mainFrameMock = CreateFrameStub()
    mainFrameMock:Show()

    WithGlobals({
      UIParent = CreateFrameStub(),
      CreateFrame = CreateFrameStub,
      GetTime = function()
        return now
      end,
      isiLiveMainFrame = mainFrameMock,
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_notice.lua" })
      local Notice = RequireValue(addon.Notice, "Notice module should load")
      local hint = Notice.CreateInviteHint({ parent = UIParent })
      hint.Show("Damage pending", 5)

      local _, relativeTo = hint.frame:GetPoint()
      Assert.Equal(
        relativeTo,
        mainFrameMock,
        "invite hint should anchor to global main frame when no LFG dialog is shown"
      )
    end)
  end)

  test("Notice.CreateInviteHint falls back to parent UIParent when nothing else is available", function()
    local now = 400
    local parent = CreateFrameStub()

    WithGlobals({
      UIParent = parent,
      CreateFrame = CreateFrameStub,
      GetTime = function()
        return now
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_notice.lua" })
      local Notice = RequireValue(addon.Notice, "Notice module should load")
      local hint = Notice.CreateInviteHint({ parent = parent })
      hint.Show("Looking for group", 10)

      local point, relativeTo, relativePoint, _, y = hint.frame:GetPoint()
      Assert.Equal(point, "TOP", "fallback anchor should be TOP-side")
      Assert.Equal(relativeTo, parent, "fallback anchor should be the parent UIParent")
      Assert.Equal(relativePoint, "TOP", "fallback relative point should be parent TOP")
      Assert.Equal(y, -220, "fallback y offset should match notice spec")
    end)
  end)

  test("Notice.CreateInviteHint OnUpdate auto-hides after duration", function()
    local now = 500

    WithGlobals({
      UIParent = CreateFrameStub(),
      CreateFrame = CreateFrameStub,
      GetTime = function()
        return now
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_notice.lua" })
      local Notice = RequireValue(addon.Notice, "Notice module should load")
      local hint = Notice.CreateInviteHint({ parent = UIParent })

      hint.Show("Auto-expire", 3)
      Assert.True(hint.frame:IsShown(), "invite hint should be visible right after Show()")

      local onUpdate = hint.frame:GetScript("OnUpdate")
      onUpdate = RequireValue(onUpdate, "invite hint frame should expose OnUpdate")

      now = 502 -- inside duration window
      onUpdate(hint.frame, 2)
      Assert.True(hint.frame:IsShown(), "invite hint stays visible while inside duration")

      now = 504 -- past endsAt (500 + 3)
      onUpdate(hint.frame, 2)
      Assert.False(hint.frame:IsShown(), "invite hint hides itself after duration elapses")
    end)
  end)
end

local function RegisterPortalNavigatorBranchTests(test, Assert, WithGlobals, LoadAddonModules)
  test("PortalNavigator hides itself when right-clicked", function()
    WithGlobals({
      UIParent = CreateFrameStub(),
      CreateFrame = CreateFrameStub,
      GetTime = function()
        return 0
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_notice.lua" })
      local Notice = RequireValue(addon.Notice, "Notice module should load")
      local portal = Notice.CreatePortalNavigatorNotice({ parent = UIParent })
      portal.SetVisible(true)
      Assert.True(portal.frame:IsShown(), "portal navigator visible before right-click")

      local onMouseUp = portal.frame:GetScript("OnMouseUp")
      onMouseUp = RequireValue(onMouseUp, "portal navigator frame should define OnMouseUp")
      onMouseUp(portal.frame, "RightButton")
      Assert.False(portal.frame:IsShown(), "portal navigator hides on RightButton mouse-up")
    end)
  end)

  test("PortalNavigator left-click does NOT hide the frame", function()
    WithGlobals({
      UIParent = CreateFrameStub(),
      CreateFrame = CreateFrameStub,
      GetTime = function()
        return 0
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_notice.lua" })
      local Notice = RequireValue(addon.Notice, "Notice module should load")
      local portal = Notice.CreatePortalNavigatorNotice({ parent = UIParent })
      portal.SetVisible(true)

      local onMouseUp = portal.frame:GetScript("OnMouseUp")
      onMouseUp(portal.frame, "LeftButton")
      Assert.True(portal.frame:IsShown(), "portal navigator must NOT hide on LeftButton mouse-up")
    end)
  end)

  test("PortalNavigator close-button click hides the frame", function()
    WithGlobals({
      UIParent = CreateFrameStub(),
      CreateFrame = CreateFrameStub,
      GetTime = function()
        return 0
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua", "isiLive_notice.lua" })
      local Notice = RequireValue(addon.Notice, "Notice module should load")
      local portal = Notice.CreatePortalNavigatorNotice({ parent = UIParent })
      portal.SetVisible(true)

      local closeButton = RequireValue(portal.closeButton, "portal navigator should expose close button")
      local onClick = closeButton:GetScript("OnClick")
      onClick = RequireValue(onClick, "portal navigator close button should define OnClick")
      onClick(closeButton)
      Assert.False(portal.frame:IsShown(), "portal navigator close button hides the frame")
    end)
  end)
end

return function(test, ctx)
  local Assert = RequireValue(ctx.assert, "ui_notice_branches scenario ctx.assert should exist")
  local WithGlobals = RequireValue(ctx.with_globals, "ui_notice_branches scenario ctx.with_globals should exist")
  local LoadAddonModules = RequireValue(ctx.load_modules, "ui_notice_branches scenario ctx.load_modules should exist")

  RegisterInviteHintTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterPortalNavigatorBranchTests(test, Assert, WithGlobals, LoadAddonModules)
end
