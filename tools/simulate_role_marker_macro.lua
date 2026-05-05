-- Standalone CLI tool: regression pin for the tank/healer role-icon macro.
--
-- Hard contract enforced by this simulator (see CLAUDE.md "Role-marker click
-- feature: target by character name"):
--
--   * The macro must target by CHARACTER NAME, never by unit token.
--     /target party1 is broken in WoW 12.0.5 (party tokens are secret unit
--     tokens; the slash command silently fails from secure macros).
--   * Same-realm units use bare "/target Name", cross-realm units use
--     "/target Name-Realm" — same shape as the existing whisper code.
--   * UTF-8 character names are passed through byte-for-byte. WoW's slash-
--     command parser handles Müller / Sébastien / Юрий / José / Çağrı /
--     Lucía / Aleksandr natively. We must NOT normalize or transliterate.
--   * If info.name is missing/empty, no macro is set (no partial macro).
--
-- This drives the real RenderRosterImpl from roster_panel_render.lua against
-- frame mocks that capture every SetAttribute call. The roster mixes locales
-- and same-realm/cross-realm to catch any byte mangling or token regression.
--
-- End-to-end discipline (CLAUDE.md "Tests & simulators: end-to-end by default"):
-- the real RenderRosterImpl is loaded; frame mocks record SetAttribute. Same
-- module-boundary exception as simulate_ready_check_frame_overrides.
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
-- Frame mocks. The role button is created with SecureActionButtonTemplate;
-- production calls SetAttribute("type1"|"type2"|"macrotext1"|"macrotext2"|...).
-- We capture each attribute keyed by the unit so the roster-name assertions
-- can look up per row.
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
    icon = icon,
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
  mock.SetFrameLevel = NoOp
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
  mock.GetFrameLevel = function()
    return 1
  end
  mock.SetFrameLevel = NoOp
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
    truncateName = function(t)
      return t
    end,
    getShortSpecLabel = function(t)
      return t
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

  -- ----------------------------------------------------------------------
  -- Scenario 1: same-realm same-locale (English) — sanity baseline.
  -- ----------------------------------------------------------------------
  print("\n========== Scenario 1: same-realm baseline (no realm suffix) ==========")
  do
    local memberRows = BuildMemberRows()
    local state = BuildState(memberRows, addon)
    local roster = {
      player = { name = "Felix", realm = "", class = "WARRIOR", role = "TANK" },
      party1 = { name = "Anna", realm = "", class = "PRIEST", role = "HEALER" },
      party2 = { name = "Bob", realm = "", class = "MAGE", role = "DAMAGER" },
      party3 = { name = "Carl", realm = "", class = "ROGUE", role = "DAMAGER" },
      party4 = { name = "Dave", realm = "", class = "WARLOCK", role = "DAMAGER" },
    }
    RI.RenderRosterImpl(state, roster)

    local tank = FindRowForUnit(memberRows, "player")
    Check(tank ~= nil, "TANK row rendered")
    if tank then
      Check(
        tank.roleButton:GetAttribute("macrotext1") == "/target Felix\n/tm 6\n/targetlasttarget",
        "TANK macrotext1 = '/target Felix\\n/tm 6\\n/targetlasttarget' (no realm, no token)"
      )
      Check(
        tank.roleButton:GetAttribute("macrotext2") == "/target Felix\n/tm 0\n/targetlasttarget",
        "TANK macrotext2 (clear) = '/target Felix\\n/tm 0\\n/targetlasttarget'"
      )
    end

    local heal = FindRowForUnit(memberRows, "party1")
    Check(heal ~= nil, "HEALER row rendered")
    if heal then
      Check(
        heal.roleButton:GetAttribute("macrotext1") == "/target Anna\n/tm 4\n/targetlasttarget",
        "HEALER macrotext1 = '/target Anna\\n/tm 4\\n/targetlasttarget'"
      )
    end

    for _, unit in ipairs({ "party2", "party3", "party4" }) do
      local dps = FindRowForUnit(memberRows, unit)
      if dps then
        Check(
          dps.roleButton:GetAttribute("macrotext1") == nil,
          "DAMAGER " .. unit .. " macrotext1 is nil (no marker for DPS)"
        )
      end
    end
  end

  -- ----------------------------------------------------------------------
  -- Scenario 2: cross-realm — realm suffix appended exactly as whisper does.
  -- ----------------------------------------------------------------------
  print("\n========== Scenario 2: cross-realm name-realm suffix ==========")
  do
    local memberRows = BuildMemberRows()
    local state = BuildState(memberRows, addon)
    local roster = {
      player = { name = "Felix", realm = "Tichondrius", class = "WARRIOR", role = "TANK" },
      party1 = { name = "Anna", realm = "TwistingNether", class = "PRIEST", role = "HEALER" },
    }
    RI.RenderRosterImpl(state, roster)

    local tank = FindRowForUnit(memberRows, "player")
    if tank then
      Check(
        tank.roleButton:GetAttribute("macrotext1") == "/target Felix-Tichondrius\n/tm 6\n/targetlasttarget",
        "TANK cross-realm macrotext1 has '-Tichondrius' suffix"
      )
    end

    local heal = FindRowForUnit(memberRows, "party1")
    if heal then
      Check(
        heal.roleButton:GetAttribute("macrotext1") == "/target Anna-TwistingNether\n/tm 4\n/targetlasttarget",
        "HEALER cross-realm macrotext1 has '-TwistingNether' suffix"
      )
    end
  end

  -- ----------------------------------------------------------------------
  -- Scenario 3: UTF-8 multi-byte names from every LFG-supported locale must
  -- pass through byte-for-byte. This is the regression pin against any
  -- accidental sanitization / transliteration.
  -- ----------------------------------------------------------------------
  print("\n========== Scenario 3: UTF-8 multi-byte names pass through unchanged ==========")
  do
    local cases = {
      -- { locale, tank, healer, expectedTankFragment, expectedHealerFragment }
      -- Decimal escapes (\DDD) are Lua 5.1 compatible; \xHH would only work on 5.2+.
      -- ü=\195\188, ä=\195\164, é=\195\169, î=\195\174, í=\195\173,
      -- ã=\195\163, ç=\195\167, ò=\195\178, ì=\195\172, Ç=\195\135,
      -- ğ=\196\159, ı=\196\177, İ=\196\176
      { "deDE", "M\195\188ller", "Sch\195\164fer", "M\195\188ller", "Sch\195\164fer" },
      { "frFR", "S\195\169bastien", "Beno\195\174t", "S\195\169bastien", "Beno\195\174t" },
      { "esES", "Luc\195\173a", "Jos\195\169", "Luc\195\173a", "Jos\195\169" },
      { "ptBR", "Jo\195\163o", "Concei\195\167\195\163o", "Jo\195\163o", "Concei\195\167\195\163o" },
      { "itIT", "Niccol\195\178", "Beatr\195\172ce", "Niccol\195\178", "Beatr\195\172ce" },
      -- Cyrillic Юрий = \208\174\209\128\208\184\208\185, Алекс = \208\144\208\187\208\181\208\186\209\129
      {
        "ruRU",
        "\208\174\209\128\208\184\208\185",
        "\208\144\208\187\208\181\208\186\209\129",
        "\208\174\209\128\208\184\208\185",
        "\208\144\208\187\208\181\208\186\209\129",
      },
      -- Turkish Çağrı = \195\135a\196\159r\196\177, İlhan = \196\176lhan
      { "trTR", "\195\135a\196\159r\196\177", "\196\176lhan", "\195\135a\196\159r\196\177", "\196\176lhan" },
    }
    for _, case in ipairs(cases) do
      local locale, tankName, healerName, tankExpect, healerExpect = case[1], case[2], case[3], case[4], case[5]
      local memberRows = BuildMemberRows()
      local state = BuildState(memberRows, addon)
      local roster = {
        player = { name = tankName, realm = "", class = "WARRIOR", role = "TANK" },
        party1 = { name = healerName, realm = "", class = "PRIEST", role = "HEALER" },
      }
      RI.RenderRosterImpl(state, roster)

      local tank = FindRowForUnit(memberRows, "player")
      if tank then
        local m1 = tank.roleButton:GetAttribute("macrotext1") or ""
        Check(
          m1 == "/target " .. tankExpect .. "\n/tm 6\n/targetlasttarget",
          locale .. ": TANK macrotext1 has UTF-8 name byte-for-byte (" .. tankExpect .. ")"
        )
      end

      local heal = FindRowForUnit(memberRows, "party1")
      if heal then
        local m1 = heal.roleButton:GetAttribute("macrotext1") or ""
        Check(
          m1 == "/target " .. healerExpect .. "\n/tm 4\n/targetlasttarget",
          locale .. ": HEALER macrotext1 has UTF-8 name byte-for-byte (" .. healerExpect .. ")"
        )
      end
    end
  end

  -- ----------------------------------------------------------------------
  -- Scenario 4: hard ban on unit tokens. No macrotext anywhere may contain
  -- partyN / raidN / target / focus / boss / nameplate — those are the
  -- secret-unit-token forms that 12.0.5 silently breaks.
  -- ----------------------------------------------------------------------
  print("\n========== Scenario 4: no macrotext contains a unit token ==========")
  do
    local memberRows = BuildMemberRows()
    local state = BuildState(memberRows, addon)
    local roster = {
      player = { name = "Felix", realm = "Tichondrius", class = "WARRIOR", role = "TANK" },
      party1 = { name = "Anna", realm = "Tichondrius", class = "PRIEST", role = "HEALER" },
    }
    RI.RenderRosterImpl(state, roster)

    local TOKEN_PATTERNS = {
      "/target party",
      "/target raid",
      "/target target",
      "/target focus",
      "/target boss",
      "/target nameplate",
      "/target arena",
    }
    for i = 1, #memberRows do
      for _, attr in ipairs({ "macrotext1", "macrotext2" }) do
        local m = memberRows[i].roleButton:GetAttribute(attr)
        if type(m) == "string" then
          for _, bad in ipairs(TOKEN_PATTERNS) do
            Check(m:find(bad, 1, true) == nil, string.format("row %d %s does NOT contain '%s'", i, attr, bad))
          end
        end
      end
    end
  end

  -- ----------------------------------------------------------------------
  -- Scenario 5: defensive — empty / nil name drops the macro entirely.
  -- Rather than emit a partial "/target \n/tm 6\n..." which would target
  -- nothing and mark the previous target.
  -- ----------------------------------------------------------------------
  print("\n========== Scenario 5: missing name => no macro at all ==========")
  do
    local memberRows = BuildMemberRows()
    local state = BuildState(memberRows, addon)
    local roster = {
      player = { name = "", realm = "", class = "WARRIOR", role = "TANK" },
      party1 = { class = "PRIEST", role = "HEALER" },
    }
    RI.RenderRosterImpl(state, roster)

    local tank = FindRowForUnit(memberRows, "player")
    if tank then
      Check(tank.roleButton:GetAttribute("macrotext1") == nil, "empty-name TANK: macrotext1 is nil")
      Check(tank.roleButton:GetAttribute("macrotext2") == nil, "empty-name TANK: macrotext2 is nil")
    end

    local heal = FindRowForUnit(memberRows, "party1")
    if heal then
      Check(heal.roleButton:GetAttribute("macrotext1") == nil, "missing-name HEALER: macrotext1 is nil")
      Check(heal.roleButton:GetAttribute("macrotext2") == nil, "missing-name HEALER: macrotext2 is nil")
    end
  end

  -- ----------------------------------------------------------------------
  -- Scenario 6: type1/type2 are wired so the secure handler routes the
  -- click to the macro. Without these, the macrotext is dead weight.
  -- ----------------------------------------------------------------------
  print("\n========== Scenario 6: type1/type2 = 'macro' for active rows ==========")
  do
    local memberRows = BuildMemberRows()
    local state = BuildState(memberRows, addon)
    local roster = {
      player = { name = "Felix", realm = "", class = "WARRIOR", role = "TANK" },
      party1 = { name = "Anna", realm = "", class = "PRIEST", role = "HEALER" },
    }
    RI.RenderRosterImpl(state, roster)

    local tank = FindRowForUnit(memberRows, "player")
    if tank then
      Check(tank.roleButton:GetAttribute("type1") == "macro", "TANK type1 = 'macro'")
      Check(tank.roleButton:GetAttribute("type2") == "macro", "TANK type2 = 'macro'")
    end
    local heal = FindRowForUnit(memberRows, "party1")
    if heal then
      Check(heal.roleButton:GetAttribute("type1") == "macro", "HEALER type1 = 'macro'")
      Check(heal.roleButton:GetAttribute("type2") == "macro", "HEALER type2 = 'macro'")
    end
  end
end)

if failures > 0 then
  print(string.format("\nRole-marker macro simulator failed: %d check(s) failed", failures))
  print("If you are intentionally changing the macro contract, update CLAUDE.md")
  print('"Role-marker click feature: target by character name" first, then update')
  print("this simulator to encode the new contract.")
  os.exit(1)
end

print("\nRole-marker macro simulator passed.")
