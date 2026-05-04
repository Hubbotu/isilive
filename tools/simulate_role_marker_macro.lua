-- Standalone CLI tool: regression pin for the tank/healer role-icon click
-- macro form, fixed in v0.9.208 after a v0.9.203 "speculative hardening"
-- broke it.
--
-- The bug class:
--   * v0.9.203 changed the secure macro from `/target party1` to
--     `/target [@party1]` as forward-looking defense against future Blizzard
--     unit-token tightening.
--   * `[@unit]` is a valid targeting CONDITIONAL for /cast and /use, but
--     `/target` does NOT parse it as a unit selector — the macro silently
--     resolves to nothing, then `/tm 6` marks whatever the previous target
--     was. From the user's perspective the click "places the marker on the
--     wrong player" or does nothing.
--   * v0.9.208 reverted to the bare-form `/target unit` (e.g. `/target party1`).
--
-- This simulator drives the real RenderRosterImpl from roster_panel_render.lua
-- against frame mocks that capture every SetAttribute call, then asserts the
-- macrotext1 / macrotext2 strings are exactly the bare-form macros for the
-- TANK and HEALER roles, and explicitly NOT the [@unit] form.
--
-- Verifies:
--   * TANK row: macrotext1 = "/target <unit>\n/tm 6\n/targetlasttarget"
--   * TANK row: macrotext2 = "/target <unit>\n/tm 0\n/targetlasttarget"
--   * HEALER row: macrotext1 = "/target <unit>\n/tm 4\n/targetlasttarget"
--   * HEALER row: macrotext2 = "/target <unit>\n/tm 0\n/targetlasttarget"
--   * DAMAGER row: macrotext1 / macrotext2 = nil (no marker buttons for DPS)
--   * No macrotext anywhere contains "[@" (the broken v0.9.203 form)
--   * type1 = type2 = "macro" so the secure handler routes the click to
--     macrotext, not to a different action.
--
-- End-to-end discipline (CLAUDE.md "Tests & simulators: end-to-end by default"):
-- the real RenderRosterImpl from the production render module is loaded;
-- frame mocks record every SetAttribute call. The same module-boundary
-- exception as simulate_ready_check_frame_overrides applies — _RosterInternal
-- / _RosterPanelInternal is reached via reflection because no public API
-- accepts the mock state object the test feeds.
--
-- COMPONENT-ONLY exception (per CLAUDE.md): see simulate_ready_check_frame_overrides
-- header — _RosterPanelInternal reflection. Documented here too.
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
-- Frame mocks. The role button is created with the SecureActionButtonTemplate;
-- production calls SetAttribute("type1"|"type2"|"macrotext1"|"macrotext2"|...).
-- We capture each attribute keyed by the unit so test assertions can lookup
-- per row.
-- ----------------------------------------------------------------------
local function NoOp() end

local function MakeRoleButtonMock()
  local icon = {
    SetAllPoints = NoOp,
    SetTexture = NoOp,
    SetTexCoord = NoOp,
    SetVertexColor = NoOp,
    SetDesaturated = NoOp,
    Show = NoOp,
    Hide = NoOp,
  }
  local mock = {
    _attributes = {},
    _shown = false,
    icon = icon, -- production CreateMemberRow attaches a Texture here
  }
  function mock:SetAttribute(key, value)
    self._attributes[key] = value
  end
  function mock:GetAttribute(key)
    return self._attributes[key]
  end
  function mock:Show()
    self._shown = true
  end
  function mock:Hide()
    self._shown = false
  end
  mock.SetSize = NoOp
  mock.SetPoint = NoOp
  mock.RegisterForClicks = NoOp
  mock.SetScript = NoOp
  mock.HookScript = NoOp
  return mock
end

local function MakeFontStringMock()
  return {
    SetText = NoOp,
    SetTextColor = NoOp,
    SetPoint = NoOp,
    SetWidth = NoOp,
    SetJustifyH = NoOp,
    Show = NoOp,
    Hide = NoOp,
  }
end

local function MakeBackgroundMock()
  return {
    visible = false,
    Show = function(self)
      self.visible = true
    end,
    Hide = function(self)
      self.visible = false
    end,
    SetColorTexture = NoOp,
    SetAllPoints = NoOp,
  }
end

local function MakeFrameMock()
  local mock = {}
  mock.Show = NoOp
  mock.Hide = NoOp
  mock.SetPoint = NoOp
  mock.SetSize = NoOp
  mock.SetAllPoints = NoOp
  mock.CreateTexture = function()
    return MakeBackgroundMock()
  end
  mock.CreateFontString = function()
    return MakeFontStringMock()
  end
  mock.SetScript = NoOp
  mock.HookScript = NoOp
  mock.RegisterEvent = NoOp
  mock.UnregisterEvent = NoOp
  mock.EnableMouse = NoOp
  return mock
end

-- Build five member rows, each with a real-shape role button mock pre-wired.
local function BuildMemberRows()
  local rows = {}
  for i = 1, 5 do
    rows[i] = {
      roleButton = MakeRoleButtonMock(),
      readyCheckBackground = MakeBackgroundMock(),
      hoverFrame = MakeFrameMock(),
      spec = MakeFontStringMock(),
      name = MakeFontStringMock(),
      realm = MakeFontStringMock(),
      key = MakeFontStringMock(),
      ilvl = MakeFontStringMock(),
      rio = MakeFontStringMock(),
      dps = MakeFontStringMock(),
      kick = MakeFontStringMock(),
    }
  end
  return rows
end

-- Build the state table RenderRosterImpl reads from. Same shape as the
-- production controller hands it, minus side-effect callbacks we don't need.
local function BuildState(memberRows, addonRoster)
  return {
    memberRows = memberRows,
    mainFrame = MakeFrameMock(),
    shareKeysButton = (function()
      local btn = MakeFrameMock()
      btn.SetEnabled = NoOp
      btn.SetAlpha = NoOp
      btn.SetShareKeysAvailable = NoOp
      return btn
    end)(),
    rosterTooltip = nil,
    setMainFrameHeightSafe = NoOp,
    minFrameHeight = 100,
    raidNoticeLabel = nil,
    buildOrderedRoster = addonRoster.Roster.BuildOrderedRoster,
    rolePriority = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 },
    unitPriority = { player = 1, party1 = 2, party2 = 3, party3 = 4, party4 = 5 },
    resolveActiveKeyOwnerUnit = function()
      return nil
    end,
    isReadyCheckActive = function()
      return false
    end,
    resolveTargetMapID = function()
      return nil
    end,
    buildDisplayData = addonRoster.Roster.BuildDisplayData,
    truncateName = function(text)
      return text
    end,
    getShortSpecLabel = function(text)
      return text
    end,
    getLanguageFlagMarkup = function()
      return ""
    end,
    getDungeonShortCode = function()
      return nil
    end,
    getDungeonName = function()
      return nil
    end,
    getRioDelta = function()
      return nil
    end,
    syncMarker = "",
    syncBadge = "",
    getPlayerSyncSummary = function()
      return nil
    end,
    getReadyCheckReadyUntil = function()
      return nil
    end,
    getReadyCheckDeclinedUntil = function()
      return nil
    end,
    getTime = function()
      return 100
    end,
    getL = function()
      return {}
    end,
    isRaidGroup = function()
      return false
    end,
    uiRef = nil,
    applyKnownKeyToRosterEntry = function()
      return false
    end,
    getPlayerLastRunDps = nil,
    getOwnedKeystoneSnapshot = nil,
    getLanguageTooltipMarkup = function()
      return ""
    end,
    showRosterColumnGuides = function()
      return false
    end,
  }
end

-- Look up the row that ended up assigned to a given unit after BuildOrderedRoster.
local function FindRowForUnit(memberRows, unit)
  for i = 1, #memberRows do
    if memberRows[i].unit == unit then
      return memberRows[i]
    end
  end
  return nil
end

-- ----------------------------------------------------------------------
-- Run.
-- ----------------------------------------------------------------------
Harness.WithGlobals({
  GetReadyCheckStatus = function()
    return nil
  end,
  RAID_CLASS_COLORS = {
    WARRIOR = { r = 0.78, g = 0.61, b = 0.43 },
    PRIEST = { r = 1, g = 1, b = 1 },
    MAGE = { r = 0.41, g = 0.8, b = 0.94 },
    ROGUE = { r = 1, g = 0.96, b = 0.41 },
    WARLOCK = { r = 0.58, g = 0.51, b = 0.79 },
  },
  CreateColor = function(r, g, b)
    return {
      GenerateHexColor = function()
        return string.format("ff%02x%02x%02x", math.floor(r * 255), math.floor(g * 255), math.floor(b * 255))
      end,
    }
  end,
  UnitIsConnected = function()
    return true
  end,
  GetTime = function()
    return 100
  end,
  IsAddOnLoaded = function()
    return false
  end,
  C_AddOns = nil,
  GetAddOnMetadata = function()
    return nil
  end,
  CreateFrame = MakeFrameMock,
}, function()
  local addon = Harness.LoadAddonModules({ "isiLive_roster.lua", "isiLive_roster_panel_render.lua" })
  local RI = addon._RosterInternal or addon._RosterPanelInternal
  if not RI then
    for _, v in pairs(addon) do
      if type(v) == "table" and type(v.RenderRosterImpl) == "function" then
        RI = v
        break
      end
    end
  end
  assert(RI, "could not locate RosterPanelInternal")

  local memberRows = BuildMemberRows()
  local state = BuildState(memberRows, addon)

  local roster = {
    player = { name = "Tank", class = "WARRIOR", role = "TANK" },
    party1 = { name = "Healer", class = "PRIEST", role = "HEALER" },
    party2 = { name = "Dps1", class = "MAGE", role = "DAMAGER" },
    party3 = { name = "Dps2", class = "ROGUE", role = "DAMAGER" },
    party4 = { name = "Dps3", class = "WARLOCK", role = "DAMAGER" },
  }

  print("\n========== Scenario 1: TANK + HEALER bare-form macros (v0.9.208 regression pin) ==========")
  RI.RenderRosterImpl(state, roster)

  -- TANK row: macrotext1 = /tm 6 (Blue Square), macrotext2 = /tm 0 (clear).
  local tankRow = FindRowForUnit(memberRows, "player")
  Check(tankRow ~= nil, "TANK row (unit=player) is rendered")
  if tankRow then
    local m1 = tankRow.roleButton:GetAttribute("macrotext1")
    local m2 = tankRow.roleButton:GetAttribute("macrotext2")
    Check(
      m1 == "/target player\n/tm 6\n/targetlasttarget",
      "TANK macrotext1 is the BARE form '/target player\\n/tm 6\\n/targetlasttarget' (no [@unit])"
    )
    Check(
      m2 == "/target player\n/tm 0\n/targetlasttarget",
      "TANK macrotext2 (clear) is the BARE form '/target player\\n/tm 0\\n/targetlasttarget'"
    )
    Check(
      type(m1) == "string" and m1:find("[@", 1, true) == nil,
      "TANK macrotext1 does NOT contain '[@' (the v0.9.203 regression form)"
    )
    Check(
      type(m2) == "string" and m2:find("[@", 1, true) == nil,
      "TANK macrotext2 does NOT contain '[@' (the v0.9.203 regression form)"
    )
    Check(tankRow.roleButton:GetAttribute("type1") == "macro", "TANK type1='macro'")
    Check(tankRow.roleButton:GetAttribute("type2") == "macro", "TANK type2='macro'")
  end

  -- HEALER row: macrotext1 = /tm 4 (Green Triangle), macrotext2 = /tm 0.
  local healerRow = FindRowForUnit(memberRows, "party1")
  Check(healerRow ~= nil, "HEALER row (unit=party1) is rendered")
  if healerRow then
    local m1 = healerRow.roleButton:GetAttribute("macrotext1")
    local m2 = healerRow.roleButton:GetAttribute("macrotext2")
    Check(
      m1 == "/target party1\n/tm 4\n/targetlasttarget",
      "HEALER macrotext1 is the BARE form '/target party1\\n/tm 4\\n/targetlasttarget' (no [@unit])"
    )
    Check(
      m2 == "/target party1\n/tm 0\n/targetlasttarget",
      "HEALER macrotext2 (clear) is the BARE form '/target party1\\n/tm 0\\n/targetlasttarget'"
    )
    Check(
      type(m1) == "string" and m1:find("[@", 1, true) == nil,
      "HEALER macrotext1 does NOT contain '[@' (the v0.9.203 regression form)"
    )
  end

  -- DAMAGER rows: no marker macrotext (the production code clears them on DPS).
  print("\n========== Scenario 2: DAMAGER rows have no marker macrotext ==========")
  for _, dpsUnit in ipairs({ "party2", "party3", "party4" }) do
    local dpsRow = FindRowForUnit(memberRows, dpsUnit)
    Check(dpsRow ~= nil, "DAMAGER row (unit=" .. dpsUnit .. ") is rendered")
    if dpsRow then
      local m1 = dpsRow.roleButton:GetAttribute("macrotext1")
      local m2 = dpsRow.roleButton:GetAttribute("macrotext2")
      Check(m1 == nil, "DAMAGER " .. dpsUnit .. " macrotext1 is nil (no marker for DPS)")
      Check(m2 == nil, "DAMAGER " .. dpsUnit .. " macrotext2 is nil (no marker for DPS)")
    end
  end

  -- Belt-and-braces: scan every row's macrotext for the broken form. A future
  -- regression that re-introduces [@unit] would be caught even if the per-role
  -- assertions above were also accidentally relaxed.
  print("\n========== Scenario 3: every macrotext is free of '[@' across the whole roster ==========")
  local sawBrokenForm = false
  for i = 1, #memberRows do
    local m1 = memberRows[i].roleButton:GetAttribute("macrotext1")
    local m2 = memberRows[i].roleButton:GetAttribute("macrotext2")
    if (type(m1) == "string" and m1:find("[@", 1, true)) or (type(m2) == "string" and m2:find("[@", 1, true)) then
      sawBrokenForm = true
    end
  end
  Check(not sawBrokenForm, "no row's macrotext contains '[@' anywhere across the whole roster")
end)

if failures > 0 then
  print(string.format("\nRole-marker macro simulator failed: %d check(s) failed", failures))
  os.exit(1)
end

print("\nRole-marker macro simulator passed.")
