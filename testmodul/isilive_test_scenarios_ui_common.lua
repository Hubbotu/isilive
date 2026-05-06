---@diagnostic disable: undefined-global

-- Branch-coverage scenarios for ui/isiLive_ui_common.lua. Targets the
-- GetLocalizedText / GetBackgroundAlpha / ApplyBgAlpha / ApplyBackdrop
-- helpers and the CreatePrivateTooltip + PreparePrivateTooltip + Hide
-- pipeline, which together account for the bulk of the file's
-- previously-uncovered branches.

local function MakeFontStringStub()
  local fs = { _text = "", _shown = false }
  function fs:SetText(text)
    self._text = tostring(text or "")
  end
  function fs:GetText()
    return self._text
  end
  function fs:SetWidth() end
  function fs:SetJustifyH() end
  function fs:SetJustifyV() end
  function fs:SetWordWrap() end
  function fs:SetNonSpaceWrap() end
  function fs:SetMaxLines() end
  function fs:SetTextColor() end
  function fs:SetFont() end
  function fs:GetFont()
    return "Fonts\\\\X.TTF", 12, "OUTLINE"
  end
  function fs:SetPoint() end
  function fs:ClearAllPoints() end
  function fs:Show()
    self._shown = true
  end
  function fs:Hide()
    self._shown = false
  end
  function fs:GetStringHeight()
    return 14
  end
  return fs
end

local function MakeFrameStub()
  local frame = {
    _shown = false,
    _backdrop = nil,
    _backdropColor = nil,
    _borderColor = nil,
    _points = {},
    _scripts = {},
    _attrs = {},
  }
  function frame:Show()
    self._shown = true
  end
  function frame:Hide()
    self._shown = false
  end
  function frame:IsShown()
    return self._shown == true
  end
  function frame:SetBackdrop(b)
    self._backdrop = b
  end
  function frame:SetBackdropColor(r, g, b, a)
    self._backdropColor = { r, g, b, a }
  end
  function frame:SetBackdropBorderColor(r, g, b, a)
    self._borderColor = { r, g, b, a }
  end
  function frame:SetPoint(...)
    table.insert(self._points, { ... })
  end
  function frame:ClearAllPoints()
    self._points = {}
  end
  function frame:SetSize() end
  function frame:SetWidth() end
  function frame:SetHeight() end
  function frame:SetFrameStrata() end
  function frame:SetFrameLevel() end
  function frame:SetScript(name, fn)
    self._scripts[name] = fn
  end
  function frame:GetEffectiveScale()
    return 1
  end
  function frame:CreateFontString()
    return MakeFontStringStub()
  end
  function frame:CreateTexture()
    local tex = {}
    function tex:SetAllPoints() end
    function tex:SetColorTexture() end
    function tex:Hide() end
    function tex:Show() end
    return tex
  end
  return frame
end

return function(test, ctx)
  local Assert = ctx.assert
  local WithGlobals = ctx.with_globals
  local LoadAddonModules = ctx.load_modules

  local function LoadUICommon(globals)
    local addon
    WithGlobals(globals or {}, function()
      addon = LoadAddonModules({ "isiLive_ui_common.lua" })
    end)
    return addon.UICommon, addon
  end

  -- GetLocalizedText -----------------------------------------------------------

  test("UICommon.GetLocalizedText returns the localized string when the key exists in the resolved locale", function()
    -- GetLocale is read lazily inside GetLocalizedText, so the call must happen
    -- inside the WithGlobals scope where the override is still active.
    WithGlobals({
      GetLocale = function()
        return "deDE"
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua" })
      addon.Texts = {
        GetLocaleTables = function()
          return {
            enUS = { TEST_KEY = "Test EN" },
            deDE = { TEST_KEY = "Test DE" },
          }
        end,
      }
      Assert.Equal(addon.UICommon.GetLocalizedText("TEST_KEY", "fb"), "Test DE", "deDE locale must win over enUS")
    end)
  end)

  test("UICommon.GetLocalizedText falls back to enUS when the resolved locale is missing", function()
    WithGlobals({
      GetLocale = function()
        return "ruRU" -- no ruRU table → fall back to enUS
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua" })
      addon.Texts = {
        GetLocaleTables = function()
          return {
            enUS = { TEST_KEY = "Test EN" },
          }
        end,
      }
      Assert.Equal(
        addon.UICommon.GetLocalizedText("TEST_KEY", "fb"),
        "Test EN",
        "missing locale must fall back to enUS"
      )
    end)
  end)

  test("UICommon.GetLocalizedText returns the fallback when the key is missing", function()
    local UICommon, addon = LoadUICommon()
    addon.Texts = {
      GetLocaleTables = function()
        return { enUS = {} }
      end,
    }
    Assert.Equal(UICommon.GetLocalizedText("MISSING", "fallback"), "fallback", "missing key returns fallback")
  end)

  test("UICommon.GetLocalizedText returns fallback for non-string or empty key input", function()
    local UICommon = LoadUICommon()
    Assert.Equal(UICommon.GetLocalizedText(nil, "fb"), "fb", "nil key returns fallback")
    Assert.Equal(UICommon.GetLocalizedText("", "fb"), "fb", "empty key returns fallback")
    Assert.Equal(UICommon.GetLocalizedText(nil, nil), "", "nil key + nil fallback returns empty string")
  end)

  test("UICommon.GetLocalizedText returns fallback when addonTable.Texts is absent", function()
    local UICommon = LoadUICommon()
    -- addon.Texts intentionally not set
    Assert.Equal(UICommon.GetLocalizedText("KEY", "fb"), "fb", "missing Texts module must fall back")
  end)

  -- GetBackgroundAlpha ---------------------------------------------------------

  test("UICommon.GetBackgroundAlpha reads the configured value from IsiLiveDB", function()
    rawset(_G, "IsiLiveDB", { bgAlpha = 0.42 })
    local UICommon = LoadUICommon()
    Assert.Equal(UICommon.GetBackgroundAlpha(), 0.42, "must read bgAlpha from IsiLiveDB")
    rawset(_G, "IsiLiveDB", nil)
  end)

  test("UICommon.GetBackgroundAlpha returns DEFAULT_BG_ALPHA when IsiLiveDB is missing or has wrong type", function()
    rawset(_G, "IsiLiveDB", nil)
    local UICommon = LoadUICommon()
    Assert.Equal(UICommon.GetBackgroundAlpha(), UICommon.DEFAULT_BG_ALPHA, "missing IsiLiveDB returns default")

    rawset(_G, "IsiLiveDB", { bgAlpha = "not-a-number" })
    Assert.Equal(UICommon.GetBackgroundAlpha(), UICommon.DEFAULT_BG_ALPHA, "non-numeric bgAlpha returns default")
    rawset(_G, "IsiLiveDB", nil)
  end)

  -- ApplyBgAlpha ---------------------------------------------------------------

  test("UICommon.ApplyBgAlpha writes the alpha into the BG_PRIMARY palette + the main/panel/settings frames", function()
    local UICommon = LoadUICommon()
    local mainFrame = MakeFrameStub()
    local panelFrame = MakeFrameStub()
    local settingsCanvas = MakeFrameStub()
    UICommon.ApplyBgAlpha({
      mainFrame = mainFrame,
      panelFrame = panelFrame,
      settingsCanvas = settingsCanvas,
    }, 0.7)

    Assert.Equal(UICommon.Colors.BG_PRIMARY[4], 0.7, "BG_PRIMARY[4] must mutate to the new alpha")
    Assert.Equal(mainFrame._backdropColor[4], 0.7, "mainFrame must receive the new alpha")
    Assert.Equal(panelFrame._backdropColor[4], 0.7, "panelFrame must receive the new alpha")
    Assert.Equal(settingsCanvas._backdropColor[4], 0.7, "settingsCanvas must receive the new alpha")
  end)

  test("UICommon.ApplyBgAlpha returns silently for non-number alpha", function()
    local UICommon = LoadUICommon()
    -- Must not throw.
    UICommon.ApplyBgAlpha({}, "not-a-number")
    UICommon.ApplyBgAlpha({}, nil)
  end)

  test("UICommon.ApplyBgAlpha tolerates a missing frames table", function()
    local UICommon = LoadUICommon()
    -- Must not throw when frames is nil.
    UICommon.ApplyBgAlpha(nil, 0.5)
    Assert.Equal(UICommon.Colors.BG_PRIMARY[4], 0.5, "palette must mutate even without frames")
  end)

  -- ApplyBackdrop --------------------------------------------------------------

  test("UICommon.ApplyBackdrop applies preset backdrop + bg + border colors when both setters exist", function()
    local UICommon = LoadUICommon()
    local frame = MakeFrameStub()
    local ok = UICommon.ApplyBackdrop(frame, "CD_BOX")
    Assert.True(ok, "ApplyBackdrop must report success for known preset")
    Assert.NotNil(frame._backdrop, "SetBackdrop must be called")
    Assert.NotNil(frame._backdropColor, "SetBackdropColor must be called for the preset bg")
    Assert.NotNil(frame._borderColor, "SetBackdropBorderColor must be called for the preset border")
  end)

  test("UICommon.ApplyBackdrop returns false for nil frame or frames without SetBackdrop", function()
    local UICommon = LoadUICommon()
    Assert.False(UICommon.ApplyBackdrop(nil, "CD_BOX"), "nil frame must short-circuit to false")
    Assert.False(UICommon.ApplyBackdrop({}, "CD_BOX"), "frame without SetBackdrop must short-circuit to false")
  end)

  test("UICommon.ApplyBackdrop returns false for unknown preset name", function()
    local UICommon = LoadUICommon()
    Assert.False(
      UICommon.ApplyBackdrop(MakeFrameStub(), "DOES_NOT_EXIST"),
      "unknown preset name must short-circuit to false"
    )
  end)

  -- Private tooltip pipeline ---------------------------------------------------

  test("UICommon.CreatePrivateTooltip + PreparePrivateTooltip + HidePrivateTooltip pipeline renders + hides", function()
    -- CreateFrame is needed to construct the tooltip frame; it returns a fresh
    -- MakeFrameStub() each call so the captured tooltip behaves like a frame.
    WithGlobals({
      CreateFrame = function()
        return MakeFrameStub()
      end,
      UIParent = MakeFrameStub(),
      GetCursorPosition = function()
        return 100, 200
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_ui_common.lua" })
      local UICommon = addon.UICommon

      local parent = MakeFrameStub()
      local tooltip = UICommon.CreatePrivateTooltip(parent)
      Assert.True(type(tooltip) == "table", "tooltip must be a table")
      Assert.True(type(tooltip.SetText) == "function", "tooltip exposes SetText (provided by EnsurePrivateTooltipAPI)")
      Assert.True(type(tooltip.AddLine) == "function", "tooltip exposes AddLine")
      Assert.True(type(tooltip.SetOwner) == "function", "tooltip exposes SetOwner")

      local owner = MakeFrameStub()
      UICommon.PreparePrivateTooltip(tooltip, owner, "ANCHOR_BOTTOM")
      tooltip:SetText("Header", 1, 1, 1)
      tooltip:AddLine("Body line", 0.8, 0.8, 0.8, true)
      tooltip:Show()

      Assert.True(tooltip._shown == true, "tooltip must be visible after Show()")
      Assert.Equal(tooltip._isiLiveTooltipLineCount, 2, "two lines (header + body) recorded")

      -- Hide pipeline must not throw and must clear the visible flag.
      UICommon.HidePrivateTooltip(tooltip)
      Assert.True(tooltip._shown == false, "tooltip must be hidden after HidePrivateTooltip")
    end)
  end)

  test("UICommon.HidePrivateTooltip is a no-op for non-table input", function()
    local UICommon = LoadUICommon()
    -- Must not throw.
    UICommon.HidePrivateTooltip(nil)
    UICommon.HidePrivateTooltip("not-a-table")
  end)

  test("UICommon.PreparePrivateTooltip is a no-op for non-table tooltip input", function()
    local UICommon = LoadUICommon()
    UICommon.PreparePrivateTooltip(nil, MakeFrameStub())
    UICommon.PreparePrivateTooltip("not-a-table", MakeFrameStub())
  end)
end
