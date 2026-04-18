local _, addonTable = ...

addonTable = addonTable or {}

local RosterPanel = {}
addonTable.RosterPanel = RosterPanel

-- Trace logger for debug output
local runtimeLog = nil

--- Set trace logger for debug output
function RosterPanel.SetTraceLogger(logger)
  runtimeLog = logger
end

local function Trace(msg)
  if runtimeLog then
    runtimeLog("RosterPanel: " .. msg)
  end
end

-- Imports from _RosterInternal (set by roster_tooltip.lua and roster_layout.lua).
-- Load-order dependency: isiLive_roster_tooltip.lua and isiLive_roster_layout.lua
-- must appear before this file in isiLive.toc (currently lines 49-50 vs 53).
-- All imports below carry hardcoded fallbacks so a load-order mistake fails
-- gracefully rather than with a nil-dereference crash.
local RI = addonTable._RosterInternal or {}
local ContextHelpers = addonTable.ContextHelpers or {}

local function GetDB()
  return rawget(_G, "IsiLiveDB")
end

-- Tooltip imports
local DisableFontStringWrapping = RI.DisableFontStringWrapping or function(_fs) end
local CreateRosterHoverTooltip = RI.CreateRosterHoverTooltip or function(...)
  local _ = ...
  return nil
end
local HideRosterHoverTooltip = RI.HideRosterHoverTooltip or function(...)
  local _ = ...
end
local AnchorRosterHoverTooltip = RI.AnchorRosterHoverTooltip or function(...)
  local _ = ...
end
local FormatCompactTooltipNumber = RI.FormatCompactTooltipNumber or function(n)
  return tostring(n or 0)
end
local ShowRosterNameFallbackTooltip = RI.ShowRosterNameFallbackTooltip or function(...)
  local _ = ...
end
local ShowRosterInfoTooltip = RI.ShowRosterInfoTooltip or function(...)
  local _ = ...
end

-- Layout imports
local LAYOUT_MODE_EXPANDED = RI.LAYOUT_MODE_EXPANDED or "expanded"
local LAYOUT_MODE_COMPACT_VERTICAL = RI.LAYOUT_MODE_COMPACT_VERTICAL or "compact_vertical"
local LAYOUT_MODE_COMPACT_HORIZONTAL = RI.LAYOUT_MODE_COMPACT_HORIZONTAL or "compact_horizontal"
local LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL = RI.LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL or "compact_main_horizontal"
local DEFAULT_LAYOUT_MODE_LAST_USED = "last_used"
local LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL_LEGACY = "compact_horizontal_2"
local FULL_FRAME_WIDTH = RI.FULL_FRAME_WIDTH or 755
local DEFAULT_MIN_FRAME_HEIGHT = RI.DEFAULT_MIN_FRAME_HEIGHT or 236
local IsCombatLockdownActive = RI.IsCombatLockdownActive or function()
  return false
end
local NormalizeLayoutMode = RI.NormalizeLayoutMode
  or function(mode)
    if mode == LAYOUT_MODE_COMPACT_VERTICAL then
      return LAYOUT_MODE_COMPACT_VERTICAL
    end
    if mode == LAYOUT_MODE_COMPACT_HORIZONTAL then
      return LAYOUT_MODE_COMPACT_HORIZONTAL
    end
    if mode == LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL or mode == LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL_LEGACY then
      return LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL
    end
    return LAYOUT_MODE_EXPANDED
  end
local function ResolveConfiguredDefaultOpenLayoutMode()
  local db = GetDB()
  if type(db) ~= "table" then
    return LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL
  end

  local layoutMode = db.rosterDefaultLayoutMode
  if layoutMode == nil or layoutMode == false or layoutMode == "" then
    return LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL
  end

  if layoutMode == DEFAULT_LAYOUT_MODE_LAST_USED then
    return DEFAULT_LAYOUT_MODE_LAST_USED
  end

  if layoutMode == LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL_LEGACY then
    return LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL
  end

  if
    layoutMode == LAYOUT_MODE_EXPANDED
    or layoutMode == LAYOUT_MODE_COMPACT_VERTICAL
    or layoutMode == LAYOUT_MODE_COMPACT_HORIZONTAL
    or layoutMode == LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL
  then
    return layoutMode
  end

  return LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL
end
local IsCompactLayoutMode = RI.IsCompactLayoutMode or function(_mode)
  return false
end
local IsHorizontalCompactLayoutMode = RI.IsHorizontalCompactLayoutMode or function(_mode)
  return false
end
local IsMainHorizontalLayoutMode = RI.IsMainHorizontalLayoutMode
  or RI.IsStackedModernLayoutMode
  or function(_mode)
    return false
  end
local GetFrameHeightForLayoutMode = RI.GetFrameHeightForLayoutMode
local CD_TRACKER_ROW_HEIGHT = RI.CD_TRACKER_ROW_HEIGHT or 20
local CreateSystemOptionToggles = RI.CreateSystemOptionToggles
local RefreshSystemOptionToggles = RI.RefreshSystemOptionToggles
local LayoutSystemOptionToggles = RI.LayoutSystemOptionToggles
local AttachSystemOptionToggleWatcher = RI.AttachSystemOptionToggleWatcher
local SetFlatButtonText = RI.SetFlatButtonText or function(_btn, _text) end
local UpdateCollapseState = RI.UpdateCollapseState
local NotifyCollapseChanged = RI.NotifyCollapseChanged
local NotifyLayoutChanged = RI.NotifyLayoutChanged or function(_ui, _layoutMode) end
local CreateModeButton = RI.CreateModeButton
local ApplyFontStringSize = RI.ApplyFontStringSize
local CreateCdTrackerRow = RI.CreateCdTrackerRow
local UpdateCdTrackerRow = RI.UpdateCdTrackerRow
local CreateKillTrackRow = RI.CreateKillTrackRow
local UpdateKillTrackRow = RI.UpdateKillTrackRow
local CreateFlatButton = RI.CreateFlatButton
local CreatePanelHeaders = RI.CreatePanelHeaders
local CreateM2ColumnGuides = RI.CreateM2ColumnGuides
local AttachPanelButtonTooltip = RI.AttachPanelButtonTooltip
local AttachModeButtonTooltip = RI.AttachModeButtonTooltip
local CreateTankHelperButtons = RI.CreateTankHelperButtons

-- Column position constants (defined in isiLive_roster_panel_chrome.lua, shared via RI).
local SPEC_COL_X = RI.SPEC_COL_X or 4
local NAME_COL_X = RI.NAME_COL_X or 93
local SERVER_COL_X = RI.SERVER_COL_X or 75
local KEY_COL_X = RI.KEY_COL_X or 216
local ILVL_COL_X = RI.ILVL_COL_X or 282
local RIO_COL_X = RI.RIO_COL_X or 318
local SPEC_COL_WIDTH = RI.SPEC_COL_WIDTH or 52
local NAME_COL_WIDTH = RI.NAME_COL_WIDTH or 122
local SERVER_COL_WIDTH = RI.SERVER_COL_WIDTH or 18
local KEY_COL_WIDTH = RI.KEY_COL_WIDTH or 62
local ILVL_COL_WIDTH = RI.ILVL_COL_WIDTH or 32
local RIO_COL_WIDTH = RI.RIO_COL_WIDTH or 70
local DPS_COL_X = RI.DPS_COL_X or (RIO_COL_X + RIO_COL_WIDTH + 2)
local DPS_COL_WIDTH = RI.DPS_COL_WIDTH or 40
local KICK_COL_X = RI.KICK_COL_X or (DPS_COL_X + DPS_COL_WIDTH + 4)
local KICK_COL_WIDTH = RI.KICK_COL_WIDTH or 58
local KICK_HOVER_WIDTH = 58
local ROLE_BUTTON_X = SPEC_COL_X + SPEC_COL_WIDTH + 4

-- These settings are temporarily hidden from Blizzard Settings.
-- Keep the runtime behavior hard-forced until the controls are re-enabled.
local FORCE_SHOW_DPS_COLUMN = true
local FORCE_MARKERS_LEADER_ONLY = false

local function RequireFunction(value, name)
  return addonTable.Validators.RequireFunction(value, name, "RosterPanel")
end

local function SendPartyChatMessage(message)
  if type(ContextHelpers.SendPartyChatMessage) == "function" then
    return ContextHelpers.SendPartyChatMessage(message)
  end

  if type(message) ~= "string" or message == "" then
    return false
  end

  local sendChatMessage = rawget(_G, "SendChatMessage")
  if type(sendChatMessage) == "function" then
    local ok = pcall(sendChatMessage, message, "PARTY")
    if ok then
      return true
    end
  end

  local chatInfo = rawget(_G, "C_ChatInfo")
  local sendChatMessageCompat = type(chatInfo) == "table" and chatInfo.SendChatMessage or nil
  if type(sendChatMessageCompat) == "function" then
    local ok = pcall(sendChatMessageCompat, message, "PARTY")
    if ok then
      return true
    end
  end

  return false
end

local function BuildKeystoneLinkText(shortCode, keyLevel)
  local level = math.floor(tonumber(keyLevel) or 0)
  return string.format("%s +%d", tostring(shortCode or "?"), level)
end

local function BuildClickableKeystoneFallback(keyMapID, keyLevel, shortCode)
  local label = BuildKeystoneLinkText(shortCode, keyLevel)
  local buildClickableKeystoneLink = type(ContextHelpers.BuildClickableKeystoneLink) == "function"
      and ContextHelpers.BuildClickableKeystoneLink
    or nil
  local keyLink = buildClickableKeystoneLink and buildClickableKeystoneLink(keyMapID, keyLevel, label) or nil
  if keyLink then
    return keyLink
  end
  return label
end

local function ResolveOwnedKeystoneSnapshot(opts)
  if type(opts.getOwnedKeystoneSnapshot) == "function" then
    local mapID, level = opts.getOwnedKeystoneSnapshot()
    local numericMapID = tonumber(mapID)
    local numericLevel = tonumber(level)
    if numericMapID and numericMapID > 0 and numericLevel and numericLevel > 0 then
      return math.floor(numericMapID), math.floor(numericLevel)
    end
  end

  local roster = opts.getRoster()
  local playerInfo = roster and roster.player
  local keyMapID = tonumber(playerInfo and playerInfo.keyMapID)
  local keyLevel = tonumber(playerInfo and playerInfo.keyLevel)
  if keyMapID and keyMapID > 0 and keyLevel and keyLevel > 0 then
    return math.floor(keyMapID), math.floor(keyLevel)
  end

  return nil, nil
end

local function BuildOwnKeyAnnounceLine(opts)
  if type(ContextHelpers.BuildOwnKeystoneAnnounceLine) == "function" then
    return ContextHelpers.BuildOwnKeystoneAnnounceLine(opts)
  end

  local keyMapID, keyLevel = ResolveOwnedKeystoneSnapshot(opts)
  if not keyMapID or not keyLevel then
    return nil
  end

  local buildKeystoneChatLink = type(ContextHelpers.BuildKeystoneChatLink) == "function"
      and ContextHelpers.BuildKeystoneChatLink
    or nil
  local keyLink = buildKeystoneChatLink and buildKeystoneChatLink(keyMapID, keyLevel) or nil
  if not keyLink then
    local short = opts.getDungeonShortCode(keyMapID)
    keyLink = BuildClickableKeystoneFallback(keyMapID, keyLevel, short)
  end

  local L = opts.getL()
  local announcePrefix = tostring(L.ANNOUNCE_PREFIX or "PartyKeys:"):gsub("%s+", "")
  return string.format("[isiLive] %s %s", announcePrefix, keyLink)
end
local function CreateStatusLine(mainFrame)
  local statusLine = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  statusLine:SetPoint("BOTTOMLEFT", 10, 6)
  statusLine:SetJustifyH("LEFT")
  statusLine:SetText("")
  return statusLine
end

local function CreateMemberRow(mainFrame, index, rosterTooltip)
  local yOffset = -52 - (index - 1) * 16
  local row = {}

  row.hoverFrame = CreateFrame("Frame", nil, mainFrame)
  row.hoverFrame:SetPoint("TOPLEFT", 4, yOffset + 2)
  -- Hover/background area now extends through the Kick column.
  -- Management buttons stay further right and remain outside this area.
  row.hoverFrame:SetWidth(KICK_COL_X + KICK_HOVER_WIDTH - 4)
  row.hoverFrame:SetHeight(16)
  if row.hoverFrame.EnableMouse then
    row.hoverFrame:EnableMouse(true)
  end

  row.hoverFrame:SetScript("OnMouseUp", function(_, button)
    if not row.unit then
      return
    end

    if button == "RightButton" then
      local name = row.tooltipName
      if name then
        local target = (row.tooltipRealm and row.tooltipRealm ~= "") and (name .. "-" .. row.tooltipRealm) or name
        local openChat = rawget(_G, "ChatFrame_OpenChat")
        if type(openChat) == "function" then
          pcall(openChat, "/w " .. target .. " ")
        end
      end
    end
  end)

  if index % 2 == 0 then
    local altBg = row.hoverFrame:CreateTexture(nil, "BACKGROUND", nil, -1)
    altBg:SetAllPoints()
    altBg:SetColorTexture(1, 1, 1, 0.03)
  end

  row.readyCheckBackground = row.hoverFrame:CreateTexture(nil, "BACKGROUND", nil, 0)
  row.readyCheckBackground:SetAllPoints()
  row.readyCheckBackground:Hide()

  row.highlight = row.hoverFrame:CreateTexture(nil, "BACKGROUND")
  row.highlight:SetAllPoints()
  row.highlight:SetColorTexture(0.3, 0.65, 1, 0.08)
  row.highlight:Hide()

  row.hoverFrame:SetScript("OnEnter", function()
    row.highlight:Show()
    if
      not ShowRosterInfoTooltip(
        rosterTooltip,
        row.hoverFrame,
        row.unit,
        row.tooltipInfo,
        row.getDungeonShortCode,
        row.getDungeonName,
        row.getPlayerLastRunDps,
        row.getLanguageTooltipMarkup,
        row.getL
      )
    then
      ShowRosterNameFallbackTooltip(rosterTooltip, row.hoverFrame, row.tooltipName, row.tooltipRealm)
    end
  end)
  row.hoverFrame:SetScript("OnLeave", function()
    row.highlight:Hide()
    HideRosterHoverTooltip(rosterTooltip)
  end)

  row.roleButton = CreateFrame("Button", nil, mainFrame, "SecureActionButtonTemplate")
  row.roleButton:SetSize(14, 14)
  row.roleButton:SetPoint("TOPLEFT", ROLE_BUTTON_X, yOffset - 1)
  row.roleButton:RegisterForClicks("AnyUp", "AnyDown")
  row.roleButton.icon = row.roleButton:CreateTexture(nil, "ARTWORK")
  row.roleButton.icon:SetAllPoints()
  row.roleButton.icon:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES")
  row.roleButton:SetScript("OnEnter", function(self)
    local tooltip = AnchorRosterHoverTooltip(rosterTooltip, self)
    if type(tooltip) == "table" and type(tooltip.SetText) == "function" then
      tooltip:SetText("Role Marker", 1, 1, 1)
      if type(tooltip.AddLine) == "function" then
        tooltip:AddLine("Click to mark unit", 1, 1, 1, true)
        tooltip:AddLine("Tank: Blue Square", 0.2, 0.4, 1, true)
        tooltip:AddLine("Healer: Green Triangle", 0.2, 1, 0.2, true)
      end
      tooltip:Show()
    end
  end)
  row.roleButton:SetScript("OnLeave", function()
    HideRosterHoverTooltip(rosterTooltip)
  end)

  row.spec = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.spec:SetPoint("TOPLEFT", SPEC_COL_X, yOffset)
  row.spec:SetJustifyH("RIGHT")
  row.spec:SetWidth(SPEC_COL_WIDTH)
  DisableFontStringWrapping(row.spec)

  row.name = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.name:SetPoint("TOPLEFT", NAME_COL_X, yOffset)
  row.name:SetJustifyH("LEFT")
  row.name:SetWidth(NAME_COL_WIDTH)
  DisableFontStringWrapping(row.name)

  row.ilvl = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.ilvl:SetPoint("TOPLEFT", ILVL_COL_X, yOffset)
  row.ilvl:SetWidth(ILVL_COL_WIDTH)
  row.ilvl:SetJustifyH("RIGHT")
  DisableFontStringWrapping(row.ilvl)

  row.key = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.key:SetPoint("TOPLEFT", KEY_COL_X, yOffset)
  row.key:SetWidth(KEY_COL_WIDTH)
  row.key:SetJustifyH("RIGHT")
  DisableFontStringWrapping(row.key)

  row.rio = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.rio:SetPoint("TOPLEFT", RIO_COL_X, yOffset)
  row.rio:SetWidth(RIO_COL_WIDTH)
  row.rio:SetJustifyH("RIGHT")
  DisableFontStringWrapping(row.rio)

  row.dps = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.dps:SetPoint("TOPLEFT", DPS_COL_X, yOffset)
  row.dps:SetWidth(DPS_COL_WIDTH)
  row.dps:SetJustifyH("RIGHT")
  DisableFontStringWrapping(row.dps)

  row.kick = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.kick:SetPoint("TOPLEFT", KICK_COL_X, yOffset)
  row.kick:SetWidth(KICK_COL_WIDTH)
  row.kick:SetJustifyH("RIGHT")
  DisableFontStringWrapping(row.kick)

  row.realm = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  row.realm:SetPoint("TOPLEFT", SERVER_COL_X, yOffset)
  row.realm:SetWidth(SERVER_COL_WIDTH)
  row.realm:SetJustifyH("LEFT")
  DisableFontStringWrapping(row.realm)

  return row
end

local function AttachControllerAccessors(controller, deps)
  function controller.GetRefreshButton()
    return deps.refreshButton
  end

  function controller.GetCountdownCancelButton()
    return deps.countdownCancelButton
  end

  function controller.GetStatusLine()
    return deps.statusLine
  end

  function controller.SetCountdownCancelText(text)
    SetFlatButtonText(deps.countdownCancelButton, tostring(text or ""))
  end

  function controller.TriggerShareKeysCooldown()
    local btn = deps.shareKeysButton
    if btn and type(btn.TriggerRemoteCooldown) == "function" then
      btn.TriggerRemoteCooldown()
    end
  end
end

local function CreateShareKeysButton(mainFrame, deps)
  local button = CreateFlatButton(mainFrame, 120, 24)
  button:SetPoint("TOPRIGHT", -10, -150)
  button._verticalY = -150
  local countdownTicker = nil
  local cooldownEndAt = nil
  local shareKeysAvailable = false
  local debounceSeconds = tonumber(deps.shareKeysDebounceSeconds) or 0
  if debounceSeconds < 0 then
    debounceSeconds = 0
  end

  local function GetCurrentTime()
    return type(deps.getTime) == "function" and tonumber(deps.getTime()) or nil
  end

  local function IsCooldownActive(now)
    if debounceSeconds <= 0 then
      return false
    end
    if not now then
      now = GetCurrentTime()
    end
    return now ~= nil and cooldownEndAt ~= nil and cooldownEndAt > now
  end

  local function RefreshShareKeysButton()
    local now = GetCurrentTime()
    local cooldownActive = IsCooldownActive(now)
    if not cooldownActive then
      cooldownEndAt = nil
    end

    if cooldownActive then
      local remaining = math.max(1, math.ceil((cooldownEndAt or 0) - now))
      local label = button._baseText or button._fullText or ""
      button._baseText = label
      SetFlatButtonText(button, string.format("%s (%ds)", label, remaining))
    else
      if button._baseText then
        button._fullText = button._baseText
        button._baseText = nil
      end
      SetFlatButtonText(button, button._fullText or "")
    end

    local enabled = shareKeysAvailable and not cooldownActive
    button:SetEnabled(enabled)
    if cooldownActive then
      button:SetAlpha(0.5)
    else
      button:SetAlpha(shareKeysAvailable and 1.0 or 0.45)
    end

    if not cooldownActive and countdownTicker then
      countdownTicker:Cancel()
      countdownTicker = nil
    end
  end

  local function StartCooldownDisplay(cooldownEnd)
    if debounceSeconds <= 0 then
      return
    end
    cooldownEndAt = cooldownEnd
    if countdownTicker then
      countdownTicker:Cancel()
      countdownTicker = nil
    end
    local C_Timer_ref = rawget(_G, "C_Timer")
    if not C_Timer_ref or type(C_Timer_ref.NewTicker) ~= "function" then
      RefreshShareKeysButton()
      return
    end
    countdownTicker = C_Timer_ref.NewTicker(1.0, function()
      RefreshShareKeysButton()
    end, debounceSeconds)
    RefreshShareKeysButton()
  end

  function button.TriggerRemoteCooldown()
    local now = GetCurrentTime()
    if not now or debounceSeconds <= 0 then
      return
    end
    if IsCooldownActive(now) then
      return
    end
    StartCooldownDisplay(now + debounceSeconds)
  end

  function button.SetShareKeysAvailable(isAvailable)
    shareKeysAvailable = isAvailable == true
    RefreshShareKeysButton()
  end

  button:SetScript("OnClick", function()
    local now = GetCurrentTime()
    if IsCooldownActive(now) then
      return
    end
    local announcedOwnKey = false
    local ownLine = BuildOwnKeyAnnounceLine({
      getL = deps.getL,
      getRoster = deps.getRoster,
      getOwnedKeystoneSnapshot = deps.getOwnedKeystoneSnapshot,
      getDungeonShortCode = deps.getDungeonShortCode,
    })
    local inGroup = deps.isInGroup() == true
    if ownLine then
      if inGroup then
        local sentOwnKey = SendPartyChatMessage(ownLine)
        if not sentOwnKey then
          print(ownLine)
        end
        announcedOwnKey = sentOwnKey == true
      else
        print(ownLine)
        announcedOwnKey = true
      end
    end
    local requestedPeers = false
    if inGroup and type(deps.sendShareKeysRequest) == "function" then
      requestedPeers = deps.sendShareKeysRequest() == true
    end
    if not announcedOwnKey and not requestedPeers then
      return
    end
    if now and debounceSeconds > 0 then
      StartCooldownDisplay(now + debounceSeconds)
    end
  end)
  AttachPanelButtonTooltip(deps.tooltipFrame, button, deps.getL, "BTN_SHARE_KEYS", "TOOLTIP_ANNOUNCE_KEYS", nil)
  return button
end

local function CreatePanelButtons(mainFrame, deps)
  local getL = deps.getL
  local isPlayerLeader = deps.isPlayerLeader

  local readyCheckButton = CreateFlatButton(mainFrame, 120, 24)
  readyCheckButton:SetPoint("TOPRIGHT", -10, -60)
  readyCheckButton._verticalY = -60
  readyCheckButton:SetScript("OnClick", function()
    if not isPlayerLeader() then
      return
    end
    if type(deps.logRuntimeTrace) == "function" then
      deps.logRuntimeTrace("[UI] btn_click name=readycheck")
    end
    local doReadyCheck = _G.DoReadyCheck
    if type(doReadyCheck) == "function" then
      pcall(doReadyCheck)
    end
  end)
  AttachPanelButtonTooltip(deps.tooltipFrame, readyCheckButton, getL, "BTN_READYCHECK", "TOOLTIP_READY", isPlayerLeader)

  local countdownButton = CreateFlatButton(mainFrame, 120, 24)
  countdownButton:SetPoint("TOPRIGHT", -10, -90)
  countdownButton._verticalY = -90
  countdownButton:SetScript("OnClick", function()
    if not isPlayerLeader() then
      return
    end
    if type(deps.logRuntimeTrace) == "function" then
      deps.logRuntimeTrace("[UI] btn_click name=countdown")
    end
    local partyInfo = rawget(_G, "C_PartyInfo")
    local doCountdown = partyInfo and partyInfo.DoCountdown or nil
    if type(doCountdown) == "function" then
      pcall(doCountdown, 10)
    end
  end)
  AttachPanelButtonTooltip(deps.tooltipFrame, countdownButton, getL, "BTN_COUNTDOWN10", "TOOLTIP_CD10", isPlayerLeader)

  local refreshButton = CreateFlatButton(mainFrame, 120, 24)
  refreshButton:SetPoint("TOPRIGHT", -10, -180)
  refreshButton._verticalY = -180
  AttachPanelButtonTooltip(deps.tooltipFrame, refreshButton, getL, "BTN_REFRESH", "TOOLTIP_REFRESH", nil)

  local shareKeysButton = CreateShareKeysButton(mainFrame, deps)

  local countdownCancelButton = CreateFlatButton(mainFrame, 120, 24)
  countdownCancelButton:SetPoint("TOPRIGHT", -10, -120)
  countdownCancelButton._verticalY = -120
  AttachPanelButtonTooltip(
    deps.tooltipFrame,
    countdownCancelButton,
    getL,
    "BTN_COUNTDOWN_CANCEL",
    "TOOLTIP_CD_CANCEL",
    isPlayerLeader
  )

  return {
    readyCheckButton = readyCheckButton,
    countdownButton = countdownButton,
    refreshButton = refreshButton,
    shareKeysButton = shareKeysButton,
    countdownCancelButton = countdownCancelButton,
  }
end

local function ConstructPanelUI(mainFrame, uiDeps)
  Trace("constructing UI, row_count=5")
  local isRaidGroupFn = uiDeps.isRaidGroup

  -- Background for visibility
  do
    local uiCommon = addonTable and addonTable.UICommon
    if type(uiCommon) == "table" and type(uiCommon.ApplyBackdrop) == "function" then
      uiCommon.ApplyBackdrop(mainFrame, "MAIN_FRAME")
    end
  end
  if mainFrame.SetWidth then
    mainFrame:SetWidth(FULL_FRAME_WIDTH)
  end

  -- All three title elements share the same Y so they sit on one horizontal line.
  local TITLE_Y = -10

  local title = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 10, TITLE_Y)
  title:SetJustifyH("LEFT")
  title:SetTextColor(1, 0.85, 0)
  title:SetShadowOffset(1, -1)
  if type(title.SetShadowColor) == "function" then
    title:SetShadowColor(0, 0, 0, 0.8)
  end
  ApplyFontStringSize(title, 14)

  local titleVersion = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titleVersion:SetPoint("LEFT", title, "RIGHT", 5, 0)
  titleVersion:SetTextColor(0.55, 0.75, 1.0)
  if type(titleVersion.SetShadowOffset) == "function" then
    titleVersion:SetShadowOffset(1, -1)
  end
  if type(titleVersion.SetShadowColor) == "function" then
    titleVersion:SetShadowColor(0, 0, 0, 0.9)
  end
  ApplyFontStringSize(titleVersion, 14)

  local titleHint = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titleHint:SetPoint("LEFT", titleVersion, "RIGHT", 6, 0)
  titleHint:SetTextColor(0.45, 0.85, 0.45)
  if type(titleHint.SetShadowOffset) == "function" then
    titleHint:SetShadowOffset(1, -1)
  end
  if type(titleHint.SetShadowColor) == "function" then
    titleHint:SetShadowColor(0, 0, 0, 0.9)
  end
  ApplyFontStringSize(titleHint, 14)

  local headers = CreatePanelHeaders(mainFrame)
  local m2ColumnGuides = CreateM2ColumnGuides(mainFrame)
  local panelTooltip = CreateRosterHoverTooltip(mainFrame)
  local getL = type(uiDeps.getL) == "function" and uiDeps.getL or function()
    return {}
  end
  local L = getL()
  local buttonDeps = {}
  for key, value in pairs(uiDeps) do
    buttonDeps[key] = value
  end
  buttonDeps.tooltipFrame = panelTooltip
  local buttons = CreatePanelButtons(mainFrame, buttonDeps)
  local rosterTooltip = CreateRosterHoverTooltip(mainFrame)
  local tankButtons, tankHeader = CreateTankHelperButtons(mainFrame, panelTooltip, uiDeps.getL)

  local cdTrackerRow = CreateCdTrackerRow(mainFrame)
  local killTrackRow = CreateKillTrackRow(mainFrame)
  local statusLine = CreateStatusLine(mainFrame)
  local optionToggles = CreateSystemOptionToggles(mainFrame)
  local raidNoticeLabel = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  raidNoticeLabel:SetPoint("TOP", 0, -100)
  local frameWidth = type(mainFrame.GetWidth) == "function" and mainFrame:GetWidth() or 400
  raidNoticeLabel:SetWidth(frameWidth - 16)
  raidNoticeLabel:SetJustifyH("CENTER")
  raidNoticeLabel:SetTextColor(1, 0.5, 0)
  raidNoticeLabel:SetWordWrap(true)
  raidNoticeLabel:Hide()

  local ui = {
    panelTooltip = panelTooltip,
    rosterTooltip = rosterTooltip,
    title = title,
    cdTrackerRow = cdTrackerRow,
    killTrackRow = killTrackRow,
    statusLine = statusLine,
    titleVersion = titleVersion,
    titleHint = titleHint,
    raidNoticeLabel = raidNoticeLabel,
    m2ColumnGuides = m2ColumnGuides,
    showRosterColumnGuides = uiDeps.showRosterColumnGuides,
    tankButtons = tankButtons,
    tankHeader = tankHeader,
    setMainFrameHeightSafe = uiDeps.setMainFrameHeightSafe,
    setMainFrameWidthSafe = uiDeps.setMainFrameWidthSafe,
    minFrameHeight = uiDeps.minFrameHeight,
    isPlayerLeader = uiDeps.isPlayerLeader,
    forceMarkersLeaderOnly = FORCE_MARKERS_LEADER_ONLY,
  }
  for k, v in pairs(headers) do
    ui[k] = v
  end
  for k, v in pairs(buttons) do
    ui[k] = v
  end
  for k, v in pairs(optionToggles) do
    ui[k] = v
  end

  ui.managementButtons = {
    ui.readyCheckButton,
    ui.countdownButton,
    ui.countdownCancelButton,
  }
  -- Buttons that always stay anchored at leadX (not visible in H mode)
  ui.columnButtons = {
    ui.shareKeysButton,
    ui.refreshButton,
  }
  ui.toolbarButtons = {
    ui.readyCheckButton,
    ui.countdownButton,
    ui.countdownCancelButton,
    ui.shareKeysButton,
    ui.refreshButton,
  }

  -- Three static mode buttons [M2][H][V] laid out left-to-right at the top-right.
  -- Each button sets the mode directly; the active mode is highlighted gold.
  ui.layoutMode = LAYOUT_MODE_EXPANDED
  ui.isCollapsed = false
  ui.modeButtons = {}
  local modeButtonDefs = {
    {
      xOffset = -88,
      label = "M2",
      target = LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL,
      width = 24,
      descriptionKey = "MODE_LAYOUT_M2",
      descriptionFallback = L.MODE_LAYOUT_M2 or "Main horizontal layout.",
    },
    {
      xOffset = -64,
      label = "H",
      target = LAYOUT_MODE_COMPACT_HORIZONTAL,
      descriptionKey = "MODE_LAYOUT_H",
      descriptionFallback = L.MODE_LAYOUT_H or "Compact horizontal layout.",
    },
    {
      xOffset = -44,
      label = "V",
      target = LAYOUT_MODE_COMPACT_VERTICAL,
      descriptionKey = "MODE_LAYOUT_V",
      descriptionFallback = L.MODE_LAYOUT_V or "Compact vertical layout.",
    },
  }
  for _, def in ipairs(modeButtonDefs) do
    local target = def.target
    local function ApplyRequestedLayoutMode()
      if isRaidGroupFn() and target ~= LAYOUT_MODE_COMPACT_HORIZONTAL then
        return
      end
      Trace(string.format("layout mode changed to %s", tostring(target)))
      ui.layoutMode = target
      local db = GetDB()
      if db then
        db.rosterLayoutMode = target
      end
      UpdateCollapseState(ui, target, mainFrame)
      NotifyCollapseChanged(ui, ui.isCollapsed)
      NotifyLayoutChanged(ui, ui.layoutMode)
    end
    local btn = CreateModeButton(mainFrame, def.xOffset, def.label, target, function()
      ApplyRequestedLayoutMode()
    end, def.width)
    AttachModeButtonTooltip(
      panelTooltip,
      btn,
      getL,
      def.label,
      def.descriptionKey,
      def.descriptionFallback,
      "TOOLTIP_LAYOUT_SWITCH",
      L.TOOLTIP_LAYOUT_SWITCH or "Click to switch layout."
    )
    table.insert(ui.modeButtons, btn)
  end
  UpdateCollapseState(ui, LAYOUT_MODE_EXPANDED, mainFrame)

  AttachSystemOptionToggleWatcher(mainFrame, ui)
  return ui
end

local function IsEntryAtTargetDungeon(targetMapID, entry, info)
  local isAtDungeon = false

  if targetMapID and entry and entry.unit then
    local mapApi = rawget(_G, "C_Map")
    local getBestMapForUnit = mapApi and mapApi.GetBestMapForUnit or nil
    if type(getBestMapForUnit) == "function" then
      local ok, playerMapID = pcall(getBestMapForUnit, entry.unit)
      if ok and playerMapID and tonumber(playerMapID) == tonumber(targetMapID) then
        isAtDungeon = true
      end
    end
  end

  if not isAtDungeon and targetMapID and info and info.syncLocMapID then
    if tonumber(info.syncLocMapID) == tonumber(targetMapID) then
      isAtDungeon = true
    end
  end

  return isAtDungeon
end

local function BuildRowDisplayData(state, entry, isReadyCheckActive, targetMapID, includeReadyCheckDecorations)
  local info = entry and entry.info or {}
  local shouldIncludeReadyCheckDecorations = includeReadyCheckDecorations == true

  return state.buildDisplayData(info, {
    unit = entry and entry.unit or nil,
    truncateName = state.truncateName,
    getShortSpecLabel = state.getShortSpecLabel,
    getLanguageFlagMarkup = state.getLanguageFlagMarkup,
    getDungeonShortCode = state.getDungeonShortCode,
    getRioDelta = state.getRioDelta,
    syncMarker = state.syncMarker,
    syncBadge = state.syncBadge,
    syncSummary = state.getPlayerSyncSummary and state.getPlayerSyncSummary(info.name, info.realm) or nil,
    isReadyCheckActive = shouldIncludeReadyCheckDecorations and isReadyCheckActive or nil,
    getReadyCheckReadyUntil = shouldIncludeReadyCheckDecorations and state.getReadyCheckReadyUntil or nil,
    getReadyCheckDeclinedUntil = shouldIncludeReadyCheckDecorations and state.getReadyCheckDeclinedUntil or nil,
    getTime = shouldIncludeReadyCheckDecorations and state.getTime or nil,
    isAtDungeon = IsEntryAtTargetDungeon(targetMapID, entry, info),
  })
end

local function ApplyRowNameDisplay(row, displayData)
  if not row or not row.name or type(row.name.SetText) ~= "function" then
    return
  end

  row.name:SetText(
    (displayData.readyCheckMarkup or "")
      .. " |c"
      .. displayData.colorHex
      .. displayData.displayName
      .. "|r"
      .. displayData.atDungeonMarker
      .. displayData.addonMarker
  )
end

local function ApplyRowSpecDisplay(row, displayData)
  if not row or not row.spec or type(row.spec.SetText) ~= "function" then
    return
  end

  row.spec:SetText("|c" .. displayData.colorHex .. displayData.specText .. "|r")
end

local function ApplyRowReadyCheckDisplay(row, displayData)
  local background = row and row.readyCheckBackground or nil
  local color = displayData and displayData.readyCheckBackgroundColor or nil
  if not background then
    return
  end

  if type(color) == "table" and #color >= 4 then
    background:SetColorTexture(color[1], color[2], color[3], color[4])
    background:Show()
  else
    background:Hide()
  end
end

local function HasReadyCheckHoldInRoster(state, roster)
  local buildOrderedRoster = type(state.buildOrderedRoster) == "function" and state.buildOrderedRoster or nil
  local getReadyCheckReadyUntil = type(state.getReadyCheckReadyUntil) == "function" and state.getReadyCheckReadyUntil
    or nil
  local getReadyCheckDeclinedUntil = type(state.getReadyCheckDeclinedUntil) == "function"
      and state.getReadyCheckDeclinedUntil
    or nil
  local getTime = type(state.getTime) == "function" and state.getTime or nil
  local now = type(getTime) == "function" and tonumber(getTime()) or nil
  if not now or not buildOrderedRoster then
    return false
  end

  for _, entry in ipairs(buildOrderedRoster(roster, state.rolePriority, state.unitPriority)) do
    local unit = entry and entry.unit or nil
    if type(unit) == "string" and unit ~= "" then
      local readyUntil = getReadyCheckReadyUntil and tonumber(getReadyCheckReadyUntil(unit)) or nil
      if readyUntil and readyUntil > now then
        return true
      end
      local declinedUntil = getReadyCheckDeclinedUntil and tonumber(getReadyCheckDeclinedUntil(unit)) or nil
      if declinedUntil and declinedUntil > now then
        return true
      end
    end
  end

  return false
end

local function SetKickCellText(cell, info)
  if not cell then
    return
  end
  if type(info) ~= "table" or info.syncHasKick == false then
    cell:SetText("|cff666666-|r")
    return
  end
  if info.syncKickOnCooldown == true then
    local secs = math.ceil(info.syncKickRemain or 0)
    if secs > 0 then
      cell:SetText(string.format("|cffff4040%ds|r", secs))
    else
      cell:SetText("|cff666666-|r")
    end
    return
  end
  if info.syncKickOnCooldown == false then
    cell:SetText("|cff44ff44ready|r")
    return
  end
  cell:SetText("|cff666666-|r")
end

local function ResolveReadyCheckActive(state)
  if type(state) ~= "table" then
    return false
  end

  local value = state.isReadyCheckActive
  if type(value) == "function" then
    local ok, result = pcall(value)
    return ok and result == true
  end

  return value == true
end

local RefreshReadyCheckStateImpl

local function RenderRosterImpl(state, roster)
  local memberCount = roster and #roster or 0
  Trace(string.format("rendering roster, member_count=%d", memberCount))
  local memberRows = state.memberRows
  local mainFrame = state.mainFrame
  local shareKeysButton = state.shareKeysButton
  local rosterTooltip = state.rosterTooltip
  local setMainFrameHeightSafe = state.setMainFrameHeightSafe
  local minFrameHeight = state.minFrameHeight
  local raidNoticeLabel = state.raidNoticeLabel
  local buildOrderedRoster = state.buildOrderedRoster
  local rolePriority = state.rolePriority
  local unitPriority = state.unitPriority
  local resolveActiveKeyOwnerUnit = state.resolveActiveKeyOwnerUnit
  local isReadyCheckActive = ResolveReadyCheckActive(state)
  local resolveTargetMapID = state.resolveTargetMapID
  local getOwnedKeystoneSnapshot = type(state.getOwnedKeystoneSnapshot) == "function" and state.getOwnedKeystoneSnapshot
    or nil
  local buildDisplayData = state.buildDisplayData
  local truncateName = state.truncateName
  local getShortSpecLabel = state.getShortSpecLabel
  local getLanguageFlagMarkup = state.getLanguageFlagMarkup
  local getLanguageTooltipMarkup = state.getLanguageTooltipMarkup
  local getDungeonShortCode = state.getDungeonShortCode
  local getDungeonName = state.getDungeonName
  local getRioDelta = state.getRioDelta
  local syncMarker = state.syncMarker
  local syncBadge = state.syncBadge
  local getPlayerSyncSummary = state.getPlayerSyncSummary
  local getPlayerLastRunDps = state.getPlayerLastRunDps
  local getReadyCheckReadyUntil = state.getReadyCheckReadyUntil
  local getReadyCheckDeclinedUntil = state.getReadyCheckDeclinedUntil
  local getTime = state.getTime
  local getL = state.getL
  local isRaidGroup = state.isRaidGroup
  local applyKnownKeyToRosterEntry = state.applyKnownKeyToRosterEntry

  if state.uiRef then
    state.uiRef.memberRows = memberRows
  end
  local layoutMode = state.uiRef and state.uiRef.layoutMode or LAYOUT_MODE_EXPANDED
  local isCollapsed = IsCompactLayoutMode(layoutMode)

  local function ClearMemberRow(row)
    row.spec:SetText("")
    row.name:SetText("")
    row.realm:SetText("")
    row.key:SetText("")
    row.ilvl:SetText("")
    row.rio:SetText("")
    row.dps:SetText("")
    if row.kick then
      row.kick:SetText("")
    end
    row.unit = nil
    row.tooltipName = nil
    row.tooltipRealm = nil
    row.tooltipInfo = nil
    row.getDungeonShortCode = nil
    row.getDungeonName = nil
    row.getPlayerLastRunDps = nil
    row.getLanguageTooltipMarkup = nil
    row.getL = nil
    if row.hoverFrame then
      HideRosterHoverTooltip(rosterTooltip)
      row.hoverFrame.unit = nil
      row.hoverFrame:Hide()
    end
    if row.readyCheckBackground then
      row.readyCheckBackground:Hide()
    end
    if row.roleButton and not IsCombatLockdownActive() then
      row.roleButton:Hide()
    end
  end

  -- If in a raid group, clear rows and skip roster render (H mode shows the tool buttons)
  if isRaidGroup and isRaidGroup() then
    for _, row in pairs(memberRows) do
      ClearMemberRow(row)
    end
    if raidNoticeLabel then
      raidNoticeLabel:Hide()
    end
    return
  end

  -- Normal case: hide notice, show rows
  if raidNoticeLabel then
    raidNoticeLabel:Hide()
  end

  -- Temporarily hidden in Settings: keep the DPS/Deaths/Kicks columns hard-enabled in runtime.
  local showDpsColumn = FORCE_SHOW_DPS_COLUMN
  if state.uiRef then
    local function setHeaderVisible(key, visible)
      local h = state.uiRef[key]
      if h then
        if visible then
          h:Show()
        else
          h:Hide()
        end
      end
    end
    setHeaderVisible("dpsHeader", showDpsColumn)
    setHeaderVisible("kickHeader", showDpsColumn)
  end

  if state.uiRef and state.uiRef.tankButtons and not IsCombatLockdownActive() then
    local isMainHorizontal = IsMainHorizontalLayoutMode(state.uiRef.layoutMode)
    local showMarkers = not isMainHorizontal
    for _, btn in ipairs(state.uiRef.tankButtons) do
      if showMarkers then
        btn:Show()
      else
        btn:Hide()
      end
    end
    if state.uiRef.tankHeader then
      if showMarkers then
        state.uiRef.tankHeader:Show()
      else
        state.uiRef.tankHeader:Hide()
      end
    end
  end

  for _, row in pairs(memberRows) do
    ClearMemberRow(row)
  end

  local index = 1
  local orderedRoster = buildOrderedRoster(roster, rolePriority, unitPriority)
  local activeKeyOwnerUnit = resolveActiveKeyOwnerUnit and resolveActiveKeyOwnerUnit() or nil
  local targetMapID = resolveTargetMapID and resolveTargetMapID() or nil
  local hasAnyKey = false

  for _, entry in ipairs(orderedRoster) do
    if index > 5 then
      break
    end

    local info = entry.info
    if info.keyLevel and tonumber(info.keyLevel) > 0 then
      hasAnyKey = true
    end

    local row = memberRows[index]
    if not row then
      row = CreateMemberRow(mainFrame, index, rosterTooltip)
      memberRows[index] = row
    end

    if row.roleButton then
      local role = info.role
      local icon = row.roleButton.icon
      local showButton = false

      if role == "TANK" then
        icon:SetTexCoord(0, 19 / 64, 22 / 64, 41 / 64)
        showButton = true
      elseif role == "HEALER" then
        icon:SetTexCoord(20 / 64, 39 / 64, 1 / 64, 20 / 64)
        showButton = true
      elseif role == "DAMAGER" then
        icon:SetTexCoord(20 / 64, 39 / 64, 22 / 64, 41 / 64)
        showButton = true
      end

      if info.isGhost then
        showButton = false
      end

      if not IsCombatLockdownActive() then
        if showButton and not isCollapsed then
          row.roleButton:Show()
          row.roleButton:SetAttribute("type1", "macro")
          row.roleButton:SetAttribute("type2", "macro")
          if role == "TANK" then
            -- Blue Square = 6
            row.roleButton:SetAttribute("macrotext1", "/target " .. entry.unit .. "\n/tm 6\n/targetlasttarget")
            row.roleButton:SetAttribute("macrotext2", "/target " .. entry.unit .. "\n/tm 0\n/targetlasttarget")
          elseif role == "HEALER" then
            -- Green Triangle = 4
            row.roleButton:SetAttribute("macrotext1", "/target " .. entry.unit .. "\n/tm 4\n/targetlasttarget")
            row.roleButton:SetAttribute("macrotext2", "/target " .. entry.unit .. "\n/tm 0\n/targetlasttarget")
          else
            row.roleButton:SetAttribute("macrotext1", nil)
            row.roleButton:SetAttribute("macrotext2", nil)
          end
        else
          row.roleButton:Hide()
        end
      end
    end

    local displayData = BuildRowDisplayData(state, entry, isReadyCheckActive, targetMapID, true)

    ApplyRowSpecDisplay(row, displayData)
    -- Skip displayData.roleIconMarkup since we render it as a secure button
    ApplyRowNameDisplay(row, displayData)
    row.realm:SetText(displayData.languageDisplay)
    if displayData.keyText ~= "-" and activeKeyOwnerUnit and entry.unit == activeKeyOwnerUnit then
      row.key:SetText("|cffff4040" .. displayData.keyText .. "|r")
    else
      row.key:SetText(displayData.keyText)
    end
    row.ilvl:SetText(displayData.ilvlText)
    row.rio:SetText(displayData.rioText)
    local showDps = FORCE_SHOW_DPS_COLUMN
    if showDps then
      local dpsText = "-"
      if type(getPlayerLastRunDps) == "function" then
        dpsText = FormatCompactTooltipNumber(getPlayerLastRunDps(info.name, info.realm)) or "-"
      end
      if dpsText == "-" and info.syncDps and info.syncDps > 0 then
        dpsText = FormatCompactTooltipNumber(info.syncDps) or "-"
      end
      row.dps:SetText(dpsText)
      row.dps:Show()
    else
      row.dps:SetText("")
      row.dps:Hide()
    end
    if row.kick then
      -- Refresh kick sync state from cache before rendering.
      if type(applyKnownKeyToRosterEntry) == "function" then
        applyKnownKeyToRosterEntry(info)
      end
      SetKickCellText(row.kick, info)
    end
    row.unit = entry.unit
    row.tooltipName = info and info.name or nil
    row.tooltipRealm = info and info.realm or nil
    row.tooltipInfo = info
    row.getDungeonShortCode = getDungeonShortCode
    row.getDungeonName = getDungeonName
    row.getPlayerLastRunDps = getPlayerLastRunDps
    row.getLanguageTooltipMarkup = getLanguageTooltipMarkup
    row.getL = getL
    if row.hoverFrame then
      row.hoverFrame.unit = entry.unit
      row.hoverFrame:Show()
      if isCollapsed then
        row.hoverFrame:Hide()
      end
    end
    index = index + 1
  end

  if not hasAnyKey and getOwnedKeystoneSnapshot then
    local ownKeyMapID, ownKeyLevel = getOwnedKeystoneSnapshot()
    hasAnyKey = tonumber(ownKeyMapID)
        and tonumber(ownKeyMapID) > 0
        and tonumber(ownKeyLevel)
        and tonumber(ownKeyLevel) > 0
      or false
  end

  if isReadyCheckActive or HasReadyCheckHoldInRoster(state, roster) then
    RefreshReadyCheckStateImpl({
      memberRows = memberRows,
      buildOrderedRoster = buildOrderedRoster,
      rolePriority = rolePriority,
      unitPriority = unitPriority,
      isReadyCheckActive = isReadyCheckActive,
      resolveTargetMapID = resolveTargetMapID,
      buildDisplayData = buildDisplayData,
      truncateName = truncateName,
      getShortSpecLabel = getShortSpecLabel,
      getLanguageFlagMarkup = getLanguageFlagMarkup,
      getDungeonShortCode = getDungeonShortCode,
      getDungeonName = getDungeonName,
      getRioDelta = getRioDelta,
      syncMarker = syncMarker,
      syncBadge = syncBadge,
      getPlayerSyncSummary = getPlayerSyncSummary,
      getReadyCheckReadyUntil = getReadyCheckReadyUntil,
      getReadyCheckDeclinedUntil = getReadyCheckDeclinedUntil,
      getTime = getTime,
    }, roster)
  end

  if type(shareKeysButton.SetShareKeysAvailable) == "function" then
    shareKeysButton.SetShareKeysAvailable(hasAnyKey)
  else
    shareKeysButton:SetEnabled(hasAnyKey)
    shareKeysButton:SetAlpha(hasAnyKey and 1 or 0.45)
  end

  local cdTrackerExtra = IsMainHorizontalLayoutMode(layoutMode) and CD_TRACKER_ROW_HEIGHT or 0
  local desiredHeight = isCollapsed and GetFrameHeightForLayoutMode(layoutMode, minFrameHeight)
    or math.max(minFrameHeight, 45 + index * 16) + cdTrackerExtra
  setMainFrameHeightSafe(desiredHeight)

  if state.uiRef then
    UpdateCollapseState(state.uiRef, layoutMode, mainFrame)
  end
end

RefreshReadyCheckStateImpl = function(state, roster)
  local buildOrderedRoster = type(state.buildOrderedRoster) == "function" and state.buildOrderedRoster or nil
  if not buildOrderedRoster then
    return
  end
  local memberRows = state.memberRows or {}
  local orderedRoster = buildOrderedRoster(roster, state.rolePriority, state.unitPriority)
  local isReadyCheckActive = ResolveReadyCheckActive(state)
  local targetMapID = state.resolveTargetMapID and state.resolveTargetMapID() or nil

  local index = 1
  for _, entry in ipairs(orderedRoster) do
    if index > 5 then
      break
    end

    local row = memberRows[index]
    if row then
      local displayData = BuildRowDisplayData(state, entry, isReadyCheckActive, targetMapID, true)
      ApplyRowReadyCheckDisplay(row, displayData)
      ApplyRowSpecDisplay(row, displayData)
      ApplyRowNameDisplay(row, displayData)
    end

    index = index + 1
  end
end

function RosterPanel.CreateController(opts)
  Trace("creating controller")
  opts = opts or {}

  local mainFrame = assert(opts.mainFrame, "isiLive: RosterPanel requires mainFrame")
  local getL = RequireFunction(opts.getL, "getL")
  local isPlayerLeader = RequireFunction(opts.isPlayerLeader, "isPlayerLeader")
  local getAddonVersionText = RequireFunction(opts.getAddonVersionText, "getAddonVersionText")
  local updateStatusLine = RequireFunction(opts.updateStatusLine, "updateStatusLine")
  local setMainFrameHeightSafe = RequireFunction(opts.setMainFrameHeightSafe, "setMainFrameHeightSafe")
  local setMainFrameWidthSafe = RequireFunction(opts.setMainFrameWidthSafe, "setMainFrameWidthSafe")
  local minFrameHeight = tonumber(opts.minFrameHeight) or DEFAULT_MIN_FRAME_HEIGHT

  local buildOrderedRoster = RequireFunction(opts.buildOrderedRoster, "buildOrderedRoster")
  local buildDisplayData = RequireFunction(opts.buildDisplayData, "buildDisplayData")
  local truncateName = RequireFunction(opts.truncateName, "truncateName")
  local getShortSpecLabel = RequireFunction(opts.getShortSpecLabel, "getShortSpecLabel")
  local getLanguageFlagMarkup = RequireFunction(opts.getLanguageFlagMarkup, "getLanguageFlagMarkup")
  local getLanguageTooltipMarkup = type(opts.getLanguageTooltipMarkup) == "function" and opts.getLanguageTooltipMarkup
    or nil
  if not getLanguageTooltipMarkup then
    local localeModule = addonTable and addonTable.Locale
    if type(localeModule) == "table" and type(localeModule.GetLanguageTooltipMarkup) == "function" then
      local locale = rawget(_G, "GetLocale") and GetLocale() or nil
      getLanguageTooltipMarkup = function(languageTag)
        return localeModule.GetLanguageTooltipMarkup(languageTag, locale)
      end
    else
      getLanguageTooltipMarkup = function(languageTag)
        return getLanguageFlagMarkup(languageTag)
      end
    end
  end
  local getDungeonShortCode = RequireFunction(opts.getDungeonShortCode, "getDungeonShortCode")
  local getDungeonName = type(opts.getDungeonName) == "function" and opts.getDungeonName or nil
  local getOwnedKeystoneSnapshot = type(opts.getOwnedKeystoneSnapshot) == "function" and opts.getOwnedKeystoneSnapshot
    or nil
  local getRioDelta = type(opts.getRioDelta) == "function" and opts.getRioDelta or nil
  local getPlayerSyncSummary = type(opts.getPlayerSyncSummary) == "function" and opts.getPlayerSyncSummary or nil
  local resolveActiveKeyOwnerUnit = RequireFunction(opts.resolveActiveKeyOwnerUnit, "resolveActiveKeyOwnerUnit")
  local getRoster = RequireFunction(opts.getRoster, "getRoster")
  local isReadyCheckActive = opts.isReadyCheckActive
  if type(isReadyCheckActive) ~= "function" and type(isReadyCheckActive) ~= "boolean" then
    isReadyCheckActive = nil
  end
  local getReadyCheckReadyUntil = type(opts.getReadyCheckReadyUntil) == "function" and opts.getReadyCheckReadyUntil
    or nil
  local getReadyCheckDeclinedUntil = type(opts.getReadyCheckDeclinedUntil) == "function"
      and opts.getReadyCheckDeclinedUntil
    or nil
  local resolveTargetMapID = type(opts.resolveTargetMapID) == "function" and opts.resolveTargetMapID or nil
  local isInGroup = RequireFunction(opts.isInGroup, "isInGroup")
  local isRaidGroup = type(opts.isRaidGroup) == "function" and opts.isRaidGroup or function()
    return false
  end
  local rolePriority = assert(opts.rolePriority, "isiLive: RosterPanel requires rolePriority")
  local unitPriority = assert(opts.unitPriority, "isiLive: RosterPanel requires unitPriority")
  local syncMarker = tostring(opts.syncMarker or "")
  local syncBadge = tostring(opts.syncBadge or "")
  local applyKnownKeyToRosterEntry = type(opts.applyKnownKeyToRosterEntry) == "function"
      and opts.applyKnownKeyToRosterEntry
    or nil
  local getTime = type(opts.getTime) == "function" and opts.getTime
    or function()
      if type(GetTime) == "function" then
        return GetTime()
      end
      return nil
    end
  local shareKeysDebounceSeconds = tonumber(opts.shareKeysDebounceSeconds) or 1
  if shareKeysDebounceSeconds < 0 then
    shareKeysDebounceSeconds = 0
  end
  local sendShareKeysRequest = type(opts.sendShareKeysRequest) == "function" and opts.sendShareKeysRequest or nil
  local getPlayerLastRunDps = type(opts.getPlayerLastRunDps) == "function" and opts.getPlayerLastRunDps or nil
  local logRuntimeTrace = type(opts.logRuntimeTrace) == "function" and opts.logRuntimeTrace or nil
  local logRuntimeTraceDeep = type(opts.logRuntimeTraceDeep) == "function" and opts.logRuntimeTraceDeep or nil
  local showRosterColumnGuides = type(opts.showRosterColumnGuides) == "function" and opts.showRosterColumnGuides
    or function()
      return false
    end

  local ui = ConstructPanelUI(mainFrame, {
    getL = getL,
    isPlayerLeader = isPlayerLeader,
    getAddonVersionText = getAddonVersionText,
    updateStatusLine = updateStatusLine,
    setMainFrameHeightSafe = setMainFrameHeightSafe,
    setMainFrameWidthSafe = setMainFrameWidthSafe,
    minFrameHeight = minFrameHeight,
    getRoster = getRoster,
    buildOrderedRoster = buildOrderedRoster,
    rolePriority = rolePriority,
    unitPriority = unitPriority,
    getDungeonShortCode = getDungeonShortCode,
    getOwnedKeystoneSnapshot = getOwnedKeystoneSnapshot,
    applyKnownKeyToRosterEntry = applyKnownKeyToRosterEntry,
    isInGroup = isInGroup,
    getTime = getTime,
    shareKeysDebounceSeconds = shareKeysDebounceSeconds,
    sendShareKeysRequest = sendShareKeysRequest,
    isRaidGroup = isRaidGroup,
    showRosterColumnGuides = showRosterColumnGuides,
    logRuntimeTrace = logRuntimeTrace,
  })

  local readyCheckButton = ui.readyCheckButton
  local countdownButton = ui.countdownButton
  local refreshButton = ui.refreshButton
  local shareKeysButton = ui.shareKeysButton
  local countdownCancelButton = ui.countdownCancelButton

  local memberRows = {}
  local cdController = nil
  local cdTrackerNeedsVisibleRescan = true

  local function IsMainFrameShown()
    return type(mainFrame.IsShown) == "function" and mainFrame:IsShown() == true
  end

  local function MarkCdTrackerDirty()
    cdTrackerNeedsVisibleRescan = true
  end

  local function MaybeRescanCdTrackerForVisibleRender()
    if not cdController or type(cdController.Scan) ~= "function" then
      return
    end
    if not IsMainFrameShown() then
      MarkCdTrackerDirty()
      return
    end
    if cdTrackerNeedsVisibleRescan then
      cdController.Scan()
      cdTrackerNeedsVisibleRescan = false
    end
  end

  local controller = {}

  function controller.ApplyLocalization()
    local L = getL()
    local titleName = tostring(L.TITLE or "isiLive")
    local addonVer = rawget(_G, "C_AddOns")
        and type(C_AddOns.GetAddOnMetadata) == "function"
        and C_AddOns.GetAddOnMetadata("isiLive", "Version")
      or nil
    local titleVer = addonVer and ("v" .. addonVer) or ""
    ui.title:SetText(titleName)
    if ui.titleVersion then
      ui.titleVersion:SetText(titleVer)
    end
    if ui.titleHint then
      ui.titleHint:SetText(tostring(L.TITLE_HINT or ""))
    end
    ui.specHeader:SetText(L.COL_SPEC)
    ui.nameHeader:SetText(L.COL_NAME)
    ui.serverHeader:SetText(L.COL_LANGUAGE)
    ui.keyHeader:SetText(L.COL_KEY)
    ui.ilvlHeader:SetText(L.COL_ILVL)
    ui.rioHeader:SetText(L.COL_RIO)
    ui.dpsHeader:SetText(L.COL_DPS)
    if ui.kickHeader then
      ui.kickHeader:SetText("Kick")
    end
    ui.leadOptionsHeader:SetText(L.LEAD_OPTIONS)
    ui.mplusManagementHeader:SetText(L.MPLUS_MANAGEMENT)
    readyCheckButton._fullText = L.BTN_READYCHECK
    readyCheckButton._hModeText = L.BTN_READYCHECK_SHORT
    countdownButton._fullText = L.BTN_COUNTDOWN10
    countdownButton._hModeText = L.BTN_COUNTDOWN10_SHORT
    countdownCancelButton._fullText = L.BTN_COUNTDOWN_CANCEL
    countdownCancelButton._hModeText = L.BTN_COUNTDOWN_CANCEL_SHORT
    shareKeysButton._fullText = L.BTN_SHARE_KEYS
    refreshButton._fullText = L.BTN_REFRESH
    local isH = IsHorizontalCompactLayoutMode(ui and ui.layoutMode)
    SetFlatButtonText(readyCheckButton, isH and readyCheckButton._hModeText or readyCheckButton._fullText)
    SetFlatButtonText(countdownButton, isH and countdownButton._hModeText or countdownButton._fullText)
    SetFlatButtonText(
      countdownCancelButton,
      isH and countdownCancelButton._hModeText or countdownCancelButton._fullText
    )
    SetFlatButtonText(refreshButton, refreshButton._fullText)
    SetFlatButtonText(shareKeysButton, shareKeysButton._fullText)
    ui.advancedCombatLoggingToggle.label:SetText(L.OPT_ADVANCED_COMBAT_LOGGING)
    ui.damageMeterResetToggle.label:SetText(L.OPT_DAMAGE_METER_RESET)
    LayoutSystemOptionToggles(ui)
    RefreshSystemOptionToggles(ui)
  end

  function controller.IsCollapsed()
    return ui.isCollapsed
  end

  function controller.GetLayoutMode()
    return ui.layoutMode
  end

  function controller.RestoreSavedState()
    local savedLayoutMode = ResolveConfiguredDefaultOpenLayoutMode()
    if savedLayoutMode == DEFAULT_LAYOUT_MODE_LAST_USED then
      local db = GetDB()
      local lastUsedLayoutMode = type(db) == "table" and db.rosterLayoutMode or nil
      if lastUsedLayoutMode == nil or lastUsedLayoutMode == false or lastUsedLayoutMode == "" then
        savedLayoutMode = LAYOUT_MODE_COMPACT_MAIN_HORIZONTAL
      else
        savedLayoutMode = lastUsedLayoutMode
      end
    end
    local db = GetDB()
    if savedLayoutMode == nil then
      savedLayoutMode = db and db.rosterLayoutMode or nil
    end
    if savedLayoutMode == nil and db and db.rosterCollapsed ~= nil then
      savedLayoutMode = db.rosterCollapsed and LAYOUT_MODE_COMPACT_VERTICAL or LAYOUT_MODE_EXPANDED
    end
    if savedLayoutMode ~= nil then
      ui.layoutMode = NormalizeLayoutMode(savedLayoutMode)
      UpdateCollapseState(ui, ui.layoutMode, mainFrame)
      NotifyCollapseChanged(ui, ui.isCollapsed)
      NotifyLayoutChanged(ui, ui.layoutMode)
    end
  end

  function controller.RefreshLayoutState()
    if type(ui) == "table" then
      UpdateCollapseState(ui, ui.layoutMode, mainFrame)
    end
  end

  function controller.SetCollapseChangedHandler(handler)
    ui.onCollapseChanged = type(handler) == "function" and handler or nil
  end

  function controller.SetLayoutChangedHandler(handler)
    ui.onLayoutChanged = type(handler) == "function" and handler or nil
  end

  function controller.UpdateLeaderButtons()
    local enabled = isPlayerLeader()
    Trace(string.format("updating leader buttons, isLeader=%s", tostring(enabled)))
    if logRuntimeTraceDeep then
      logRuntimeTraceDeep(function()
        return string.format("[ROSTER_UI] leader_buttons enabled=%s", tostring(enabled))
      end)
    end
    readyCheckButton:SetEnabled(enabled)
    countdownButton:SetEnabled(enabled)
    countdownCancelButton:SetEnabled(enabled)
    readyCheckButton:SetAlpha(enabled and 1 or 0.45)
    countdownButton:SetAlpha(enabled and 1 or 0.45)
    countdownCancelButton:SetAlpha(enabled and 1 or 0.45)
    RefreshSystemOptionToggles(ui)
    updateStatusLine()
  end

  function controller.RenderRoster(roster)
    MaybeRescanCdTrackerForVisibleRender()
    if logRuntimeTraceDeep then
      logRuntimeTraceDeep(function()
        local count = 0
        for _ in pairs(roster or {}) do
          count = count + 1
        end
        return string.format(
          "[ROSTER_UI] render_roster entries=%s frameShown=%s layout=%s raid=%s",
          tostring(count),
          tostring(IsMainFrameShown()),
          tostring(ui.layoutMode),
          tostring(isRaidGroup())
        )
      end)
    end
    RenderRosterImpl({
      memberRows = memberRows,
      mainFrame = mainFrame,
      shareKeysButton = shareKeysButton,
      rosterTooltip = ui.rosterTooltip,
      setMainFrameHeightSafe = setMainFrameHeightSafe,
      minFrameHeight = minFrameHeight,
      buildOrderedRoster = buildOrderedRoster,
      rolePriority = rolePriority,
      unitPriority = unitPriority,
      resolveActiveKeyOwnerUnit = resolveActiveKeyOwnerUnit,
      isReadyCheckActive = isReadyCheckActive,
      resolveTargetMapID = resolveTargetMapID,
      buildDisplayData = buildDisplayData,
      truncateName = truncateName,
      getShortSpecLabel = getShortSpecLabel,
      getLanguageFlagMarkup = getLanguageFlagMarkup,
      getLanguageTooltipMarkup = getLanguageTooltipMarkup,
      getDungeonShortCode = getDungeonShortCode,
      getOwnedKeystoneSnapshot = getOwnedKeystoneSnapshot,
      getDungeonName = getDungeonName,
      getRioDelta = getRioDelta,
      syncMarker = syncMarker,
      syncBadge = syncBadge,
      getPlayerSyncSummary = getPlayerSyncSummary,
      getPlayerLastRunDps = getPlayerLastRunDps,
      getReadyCheckReadyUntil = getReadyCheckReadyUntil,
      getReadyCheckDeclinedUntil = getReadyCheckDeclinedUntil,
      getTime = getTime,
      getL = getL,
      isRaidGroup = isRaidGroup,
      raidNoticeLabel = ui.raidNoticeLabel,
      uiRef = ui,
      applyKnownKeyToRosterEntry = applyKnownKeyToRosterEntry,
    }, roster)
    RefreshSystemOptionToggles(ui)
    UpdateCdTrackerRow(ui.cdTrackerRow, cdController)
    UpdateKillTrackRow(ui.killTrackRow)
  end

  function controller.RefreshReadyCheckState(roster)
    RefreshReadyCheckStateImpl({
      memberRows = memberRows,
      buildOrderedRoster = buildOrderedRoster,
      rolePriority = rolePriority,
      unitPriority = unitPriority,
      isReadyCheckActive = isReadyCheckActive,
      resolveTargetMapID = resolveTargetMapID,
      buildDisplayData = buildDisplayData,
      truncateName = truncateName,
      getShortSpecLabel = getShortSpecLabel,
      getLanguageFlagMarkup = getLanguageFlagMarkup,
      getDungeonShortCode = getDungeonShortCode,
      getDungeonName = getDungeonName,
      getRioDelta = getRioDelta,
      syncMarker = syncMarker,
      syncBadge = syncBadge,
      getPlayerSyncSummary = getPlayerSyncSummary,
      getReadyCheckReadyUntil = getReadyCheckReadyUntil,
      getReadyCheckDeclinedUntil = getReadyCheckDeclinedUntil,
      getTime = getTime,
    }, roster or getRoster())
  end

  function controller.RefreshSystemOptionToggles()
    RefreshSystemOptionToggles(ui)
  end

  function controller.RefreshKickColumn()
    for _, row in pairs(memberRows) do
      if row.kick and row.tooltipInfo then
        local info = row.tooltipInfo
        if type(applyKnownKeyToRosterEntry) == "function" then
          applyKnownKeyToRosterEntry(info)
        end
        SetKickCellText(row.kick, info)
      end
    end
  end

  function controller.SetCdController(ctrl)
    cdController = ctrl
    MarkCdTrackerDirty()
  end

  function controller.RefreshCdTracker()
    cdTrackerNeedsVisibleRescan = false
    UpdateCdTrackerRow(ui.cdTrackerRow, cdController)
  end

  function controller.RefreshKillTrackRow()
    UpdateKillTrackRow(ui.killTrackRow)
  end

  function controller.MarkCdTrackerDirty()
    MarkCdTrackerDirty()
  end

  AttachControllerAccessors(controller, {
    refreshButton = refreshButton,
    countdownCancelButton = countdownCancelButton,
    statusLine = ui.statusLine,
    shareKeysButton = shareKeysButton,
  })

  return controller
end
