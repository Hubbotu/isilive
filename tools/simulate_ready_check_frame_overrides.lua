-- Pinpoints the "background flickers and disappears after READY_CHECK_FINISHED" bug
-- by replacing the row.readyCheckBackground frame with a mock that records every
-- Show/Hide/SetColorTexture call. Then exercises the renders that follow FINISHED
-- (RefreshReadyCheckStateImpl + RenderRosterImpl + a follow-up RenderRosterImpl
-- triggered by a fake GROUP_ROSTER_UPDATE-like event) and prints the call log.
---@diagnostic disable-next-line: undefined-global
local io = io
---@diagnostic disable-next-line: undefined-global
local load = load

local function LoadLocal(path)
  local file = assert(io.open(path, "rb"))
  local source = file:read("*a")
  file:close()
  local chunk, err = (loadstring or load)(source, "@" .. path)
  assert(chunk, err)
  return chunk()
end

local Harness = LoadLocal("testmodul/isilive_test_harness.lua")

-- Simulated state (same as the lifecycle simulator) ----------------------------------------
local sim = {
  now = 100,
  isReadyCheckActive = false,
  readyCheckStatus = {},
  readyUntilByUnit = {},
  declinedUntilByUnit = {},
}

local roster = {
  player = { name = "Tank", class = "WARRIOR", role = "TANK" },
  party1 = { name = "Healer", class = "PRIEST", role = "HEALER" },
  party2 = { name = "Dps1", class = "MAGE", role = "DAMAGER" },
  party3 = { name = "Dps2", class = "ROGUE", role = "DAMAGER" },
  party4 = { name = "Dps3", class = "WARLOCK", role = "DAMAGER" },
}

local rolePriority = { TANK = 1, HEALER = 2, DAMAGER = 3, NONE = 4 }
local unitPriority = { player = 1, party1 = 2, party2 = 3, party3 = 4, party4 = 5 }

-- Frame mock factories ----------------------------------------------------------------------

local frameLog = {}
local function LogFrame(slot, action, detail)
  table.insert(frameLog, string.format("    [%d] row=%s %s%s", #frameLog + 1, slot, action, detail or ""))
end

local function MakeBackgroundMock(slot)
  local mock = {
    visible = false,
    lastColor = nil,
  }
  function mock:Show()
    self.visible = true
    LogFrame(slot, "Background:Show", "")
  end
  function mock:Hide()
    self.visible = false
    LogFrame(slot, "Background:Hide", "")
  end
  function mock:SetColorTexture(r, g, b, a)
    self.lastColor = { r, g, b, a }
    LogFrame(slot, "Background:SetColorTexture", string.format(" rgba=(%.2f,%.2f,%.2f,%.2f)", r, g, b, a))
  end
  function mock:SetAllPoints() end
  return mock
end

local function NoOp() end
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

local function MakeFrameMock()
  local mock = {}
  function mock:Show() end
  function mock:Hide() end
  function mock:SetPoint() end
  function mock:SetSize() end
  function mock:SetAllPoints() end
  function mock:CreateTexture()
    return MakeBackgroundMock("?")
  end
  function mock:CreateFontString()
    return MakeFontStringMock()
  end
  function mock:SetScript() end
  function mock:HookScript() end
  function mock:RegisterEvent() end
  function mock:UnregisterEvent() end
  function mock:EnableMouse() end
  return mock
end

-- Build a memberRows table that already has 5 rows wired up with our mocks.
local function BuildMemberRows()
  local rows = {}
  for i = 1, 5 do
    local row = {
      readyCheckBackground = MakeBackgroundMock(i),
      hoverFrame = MakeFrameMock(),
      spec = MakeFontStringMock(),
      name = MakeFontStringMock(),
      realm = MakeFontStringMock(),
      key = MakeFontStringMock(),
      ilvl = MakeFontStringMock(),
      rio = MakeFontStringMock(),
      dps = MakeFontStringMock(),
      kick = MakeFontStringMock(),
      roleButton = nil,
      unit = nil,
    }
    rows[i] = row
  end
  return rows
end

-- Stub state object passed to RenderRosterImpl / RefreshReadyCheckStateImpl ------------------

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
    rolePriority = rolePriority,
    unitPriority = unitPriority,
    resolveActiveKeyOwnerUnit = function()
      return nil
    end,
    isReadyCheckActive = function()
      return sim.isReadyCheckActive
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
    getReadyCheckReadyUntil = function(unit)
      return sim.readyUntilByUnit[unit]
    end,
    getReadyCheckDeclinedUntil = function(unit)
      return sim.declinedUntilByUnit[unit]
    end,
    getTime = function()
      return sim.now
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

-- Run scenario -------------------------------------------------------------------------------

local function ResetLog()
  frameLog = {}
end

local function PrintLog(label)
  print(
    string.format(
      "\n---- %s [t=%d, active=%s, frameCallsRecorded=%d]",
      label,
      sim.now,
      tostring(sim.isReadyCheckActive),
      #frameLog
    )
  )
  for _, entry in ipairs(frameLog) do
    print(entry)
  end
end

local function PrintBackgroundStates(label, memberRows)
  print(string.format("\n>>> %s — current visible state of each row's background:", label))
  for i = 1, 5 do
    local bg = memberRows[i].readyCheckBackground
    local color = bg.lastColor
    local colorStr = color and string.format("rgba=(%.2f,%.2f,%.2f,%.2f)", color[1], color[2], color[3], color[4])
      or "(none)"
    print(string.format("    row[%d]: visible=%s color=%s", i, tostring(bg.visible), colorStr))
  end
end

Harness.WithGlobals({
  GetReadyCheckStatus = function(unit)
    return sim.readyCheckStatus[unit]
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
    return sim.now
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
  -- Load roster (provides Roster.BuildDisplayData + BuildOrderedRoster) and roster_panel_render.
  local addon = Harness.LoadAddonModules({ "isiLive_roster.lua", "isiLive_roster_panel_render.lua" })
  local RI = addon._RosterInternal or addon._RosterPanelInternal
  -- Try common internal table names; the render module exposes RI = RosterPanelInternal
  if not RI then
    -- Fallback: search addon table for RenderRosterImpl
    for _, v in pairs(addon) do
      if type(v) == "table" and type(v.RenderRosterImpl) == "function" then
        RI = v
        break
      end
    end
  end
  if not RI then
    error("could not locate RosterPanelInternal — render module did not expose RI")
  end

  local memberRows = BuildMemberRows()
  local state = BuildState(memberRows, addon)

  -- ===== Simulate the bug path =====
  print("========== Frame-mock reproducer for 'background flickers, disappears after FINISHED' ==========")

  -- Phase 1: ready check active, all "waiting"
  sim.isReadyCheckActive = true
  for unit in pairs(roster) do
    sim.readyCheckStatus[unit] = "waiting"
  end
  ResetLog()
  RI.RefreshReadyCheckStateImpl(state, roster)
  PrintLog("Phase 1: READY_CHECK fired → RefreshReadyCheckStateImpl (live: yellow for everyone)")
  PrintBackgroundStates("after phase 1", memberRows)

  -- Phase 2: confirms received
  sim.readyCheckStatus.player = "ready"
  sim.readyCheckStatus.party1 = "ready"
  sim.readyCheckStatus.party2 = "notready"
  -- party3 + party4 stay "waiting" (no answer)
  ResetLog()
  RI.RefreshReadyCheckStateImpl(state, roster)
  PrintLog("Phase 2: confirms in → RefreshReadyCheckStateImpl (live: green/red/yellow)")
  PrintBackgroundStates("after phase 2", memberRows)

  -- Phase 3: READY_CHECK_FINISHED — simulate post-finish state.
  -- WoW clears the live status and the event handler promotes ready/declined to hold.
  sim.now = sim.now + 3
  sim.isReadyCheckActive = false
  for unit in pairs(sim.readyCheckStatus) do
    sim.readyCheckStatus[unit] = nil
  end
  -- player + party1 → ready hold
  sim.readyUntilByUnit.player = sim.now + 20
  sim.readyUntilByUnit.party1 = sim.now + 20
  -- party2 → declined hold (explicit notready)
  sim.declinedUntilByUnit.party2 = sim.now + 20
  -- party3 + party4 → declined hold (promoted from waiting)
  sim.declinedUntilByUnit.party3 = sim.now + 20
  sim.declinedUntilByUnit.party4 = sim.now + 20

  ResetLog()
  RI.RefreshReadyCheckStateImpl(state, roster)
  PrintLog("Phase 3a: READY_CHECK_FINISHED → RefreshReadyCheckStateImpl (hold: green/red)")
  PrintBackgroundStates("after phase 3a (hold should be ON)", memberRows)

  -- Phase 4: simulate a follow-up generic UI rerender — this is what the user
  -- sees as "background disappears". A GROUP_ROSTER_UPDATE-like event, or
  -- INSPECT_READY, or any ChatMsgAddon → ctx.updateUI() → RenderRosterImpl.
  ResetLog()
  RI.RenderRosterImpl(state, roster)
  PrintLog("Phase 3b: follow-up RenderRosterImpl (the suspected override path)")
  PrintBackgroundStates("after phase 3b — IS THE HOLD STILL ON?", memberRows)

  -- Phase 5: another follow-up shortly after
  sim.now = sim.now + 2
  ResetLog()
  RI.RenderRosterImpl(state, roster)
  PrintLog("Phase 3c: another RenderRosterImpl 2s later")
  PrintBackgroundStates("after phase 3c", memberRows)
end)
