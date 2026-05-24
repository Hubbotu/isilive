local _, addonTable = ...
addonTable = addonTable or {}

local SettingsSupport = {}
addonTable.SettingsSupport = SettingsSupport

local CreateSectionHeader = addonTable.SettingsControls.CreateSectionHeader
local MeasureWrappedTextHeight = addonTable.SettingsControls.MeasureWrappedTextHeight
local CreateSectionNote = addonTable.SettingsControls.CreateSectionNote
local CreateSettingsCheckbox = addonTable.SettingsControls.CreateSettingsCheckbox
local CreateSettingsActionButton = addonTable.SettingsControls.CreateSettingsActionButton

local PADDING_X = 16
local LINE_HEIGHT = 28
local SETTINGS_CONTENT_WIDTH = 700
local BETA_ISSUES_URL = "https://github.com/byi77/isilive/issues"

local function SetLocalizedText(control, labels, key, fallback)
  if control and type(control.SetText) == "function" then
    control:SetText(labels[key] or fallback)
  end
end

function SettingsSupport.BuildChatSection(canvas, yOffset, labels, config, controls)
  controls.chatHeader, yOffset =
    CreateSectionHeader(canvas, yOffset, labels.SETTINGS_SECTION_CHAT or "Chat Announcements")
  if controls.chatHeader then
    controls.chatHeader._sectionKey = "SETTINGS_SECTION_CHAT"
  end

  controls.chatHint, yOffset = CreateSectionNote(
    canvas,
    yOffset,
    labels.SETTINGS_SECTION_CHAT_HINT or "Toggle automatic chat messages during Mythic+ runs."
  )
  if controls.chatHint then
    controls.chatHint._sectionKey = "SETTINGS_SECTION_CHAT"
  end

  controls.chatAnnounceBR, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_CHAT_BR_ANNOUNCE or "Chat: Announce Battle Res usage in M+",
    function()
      local db = config.getDB()
      return db.chatAnnounceBR ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.chatAnnounceBR = checked
    end,
    "SETTINGS_CHAT_BR_ANNOUNCE"
  )

  controls.chatAnnounceLust, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_CHAT_LUST_ANNOUNCE or "Chat: Announce Bloodlust casts in M+",
    function()
      local db = config.getDB()
      return db.chatAnnounceLust ~= false
    end,
    function(checked)
      local db = config.getDB()
      db.chatAnnounceLust = checked
    end,
    "SETTINGS_CHAT_LUST_ANNOUNCE"
  )

  return yOffset
end

function SettingsSupport.BuildDebugSection(canvas, yOffset, labels, config, controls)
  controls.debugHeader, yOffset = CreateSectionHeader(canvas, yOffset, labels.SETTINGS_SECTION_DEBUG or "Debug")
  controls.debugHint, yOffset = CreateSectionNote(
    canvas,
    yOffset,
    labels.SETTINGS_SECTION_DEBUG_HINT or "Logs reset on reload and help with support."
  )
  if controls.debugHint then
    controls.debugHint._sectionKey = "SETTINGS_SECTION_DEBUG"
  end

  controls.queueDebug, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_QUEUE_DEBUG or "Queue Debug Log (resets on reload)",
    function()
      if type(config.getQueueDebugEnabled) == "function" then
        return config.getQueueDebugEnabled()
      end
      return false
    end,
    function(checked)
      if type(config.onQueueDebugToggle) == "function" then
        config.onQueueDebugToggle(checked)
      end
    end,
    "SETTINGS_QUEUE_DEBUG"
  )

  controls.clearQueueDebugBtn, yOffset = CreateSettingsActionButton(
    canvas,
    yOffset,
    labels.SETTINGS_QUEUE_DEBUG_CLEAR or "Clear Queue Debug Log",
    240,
    function()
      if type(config.onClearQueueDebugLog) == "function" then
        config.onClearQueueDebugLog()
      end
    end,
    "SETTINGS_QUEUE_DEBUG_CLEAR",
    nil
  )

  controls.runtimeLog, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_RUNTIME_LOG or "Runtime Log (resets on reload)",
    function()
      if type(config.getRuntimeLogEnabled) == "function" then
        return config.getRuntimeLogEnabled()
      end
      return false
    end,
    function(checked)
      if type(config.onRuntimeLogToggle) == "function" then
        config.onRuntimeLogToggle(checked)
      end
    end,
    "SETTINGS_RUNTIME_LOG"
  )

  controls.clearRuntimeLogBtn, yOffset = CreateSettingsActionButton(
    canvas,
    yOffset,
    labels.SETTINGS_RUNTIME_LOG_CLEAR or "Clear Runtime Log",
    240,
    function()
      if type(config.onClearRuntimeLog) == "function" then
        config.onClearRuntimeLog()
      end
    end,
    "SETTINGS_RUNTIME_LOG_CLEAR",
    nil
  )

  controls.columnGuides, yOffset = CreateSettingsCheckbox(
    canvas,
    yOffset,
    labels.SETTINGS_ROSTER_COLUMN_GUIDES or "Column Guides",
    function()
      local db = config.getDB()
      return db.showRosterColumnGuides == true
    end,
    function(checked)
      local db = config.getDB()
      db.showRosterColumnGuides = checked
      if type(config.onRosterColumnGuidesToggle) == "function" then
        config.onRosterColumnGuidesToggle(checked)
      end
    end,
    "SETTINGS_ROSTER_COLUMN_GUIDES"
  )

  return yOffset
end

function SettingsSupport.BuildResetSection(canvas, yOffset, labels, config, controls)
  controls.resetHint, yOffset = CreateSectionNote(
    canvas,
    yOffset,
    labels.SETTINGS_SECTION_RESET_HINT or "Use these actions to restore the frame or all settings."
  )
  if controls.resetHint then
    controls.resetHint._sectionKey = "SETTINGS_SECTION_RESET"
  end
  controls.resetDBBtn, yOffset = CreateSettingsActionButton(
    canvas,
    yOffset,
    labels.SETTINGS_RESET_DB or "Reset All Settings",
    320,
    function()
      if type(config.onResetDB) == "function" then
        config.onResetDB()
      end
    end,
    {
      settingKey = "SETTINGS_RESET_DB",
      confirmText = labels.SETTINGS_RESET_CONFIRM_TEXT or "Do you really want to reset?",
    }
  )

  return yOffset
end

function SettingsSupport.BuildBetaSection(canvas, yOffset, labels, controls)
  controls.betaHeader, yOffset = CreateSectionHeader(canvas, yOffset, labels.SETTINGS_BETA_NOTICE or "Beta")

  local noticeText = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  noticeText:SetTextColor(1, 0.75, 0.2, 1)
  noticeText:SetPoint("TOPLEFT", canvas, "TOPLEFT", PADDING_X, yOffset - 4)
  noticeText:SetJustifyH("LEFT")
  noticeText:SetWidth(math.max(240, SETTINGS_CONTENT_WIDTH - (PADDING_X * 2)))
  if type(noticeText.SetWordWrap) == "function" then
    noticeText:SetWordWrap(true)
  end
  noticeText:SetText(labels.BETA_NOTICE_TEXT or "This addon is in BETA status. Please report bugs at:")
  controls.betaNoticeText = noticeText

  yOffset = yOffset - MeasureWrappedTextHeight(noticeText, LINE_HEIGHT, 6)

  local function CreateBetaUrlBox(text, offsetY)
    local urlBox = CreateFrame("EditBox", nil, canvas, "InputBoxTemplate")
    urlBox:SetSize(SETTINGS_CONTENT_WIDTH - (PADDING_X * 2) - 12, 20)
    urlBox:SetPoint("TOPLEFT", canvas, "TOPLEFT", PADDING_X + 6, offsetY - 4)
    urlBox:SetAutoFocus(false)
    urlBox:SetText(text)
    urlBox:SetCursorPosition(0)
    urlBox:SetScript("OnEscapePressed", function(self)
      self:ClearFocus()
    end)
    urlBox:SetScript("OnEditFocusGained", function(self)
      self:HighlightText()
    end)
    return urlBox
  end

  local urlBox = CreateFrame("EditBox", nil, canvas, "InputBoxTemplate")
  urlBox:SetSize(SETTINGS_CONTENT_WIDTH - (PADDING_X * 2) - 12, 20)
  urlBox:SetPoint("TOPLEFT", canvas, "TOPLEFT", PADDING_X + 6, yOffset - 4)
  urlBox:SetAutoFocus(false)
  urlBox:SetText(BETA_ISSUES_URL)
  urlBox:SetCursorPosition(0)
  urlBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  urlBox:SetScript("OnEditFocusGained", function(self)
    self:HighlightText()
  end)
  controls.betaUrlBox = urlBox

  yOffset = yOffset - LINE_HEIGHT

  local betaCommentsUrl = "https://www.curseforge.com/wow/addons/isilive/comments"
  controls.betaCommentsUrlBox = CreateBetaUrlBox(betaCommentsUrl, yOffset)

  return yOffset - LINE_HEIGHT
end

function SettingsSupport.RefreshControls(controls, labels, db, config)
  SetLocalizedText(controls.chatHeader, labels, "SETTINGS_SECTION_CHAT", "Chat Announcements")
  SetLocalizedText(
    controls.chatHint,
    labels,
    "SETTINGS_SECTION_CHAT_HINT",
    "Toggle automatic chat messages during Mythic+ runs."
  )
  if controls.chatAnnounceBR and controls.chatAnnounceBR.label then
    controls.chatAnnounceBR.label:SetText(labels.SETTINGS_CHAT_BR_ANNOUNCE or "Chat: Announce Battle Res usage in M+")
    controls.chatAnnounceBR.check:SetChecked(db.chatAnnounceBR ~= false)
  end
  if controls.chatAnnounceLust and controls.chatAnnounceLust.label then
    controls.chatAnnounceLust.label:SetText(labels.SETTINGS_CHAT_LUST_ANNOUNCE or "Chat: Announce Bloodlust casts in M+")
    controls.chatAnnounceLust.check:SetChecked(db.chatAnnounceLust ~= false)
  end

  if controls.debugHeader then
    controls.debugHeader:SetText(labels.SETTINGS_SECTION_DEBUG or "Debug")
  end
  if controls.debugHint then
    controls.debugHint:SetText(labels.SETTINGS_SECTION_DEBUG_HINT or "Logs reset on reload and help with support.")
  end
  if controls.queueDebug then
    controls.queueDebug.label:SetText(labels.SETTINGS_QUEUE_DEBUG or "Queue Debug Log")
    controls.queueDebug.check:SetChecked(
      type(config.getQueueDebugEnabled) == "function" and config.getQueueDebugEnabled() or false
    )
  end
  if controls.runtimeLog then
    controls.runtimeLog.label:SetText(labels.SETTINGS_RUNTIME_LOG or "Runtime Log")
    controls.runtimeLog.check:SetChecked(
      type(config.getRuntimeLogEnabled) == "function" and config.getRuntimeLogEnabled() or false
    )
  end
  if controls.clearQueueDebugBtn and controls.clearQueueDebugBtn.label then
    controls.clearQueueDebugBtn.label:SetText(labels.SETTINGS_QUEUE_DEBUG_CLEAR or "Clear Queue Debug Log")
  end
  if controls.clearRuntimeLogBtn and controls.clearRuntimeLogBtn.label then
    controls.clearRuntimeLogBtn.label:SetText(labels.SETTINGS_RUNTIME_LOG_CLEAR or "Clear Runtime Log")
  end
  if controls.columnGuides then
    controls.columnGuides.label:SetText(labels.SETTINGS_ROSTER_COLUMN_GUIDES or "Column Guides")
    controls.columnGuides.check:SetChecked(db.showRosterColumnGuides == true)
  end

  if controls.resetDBBtn then
    controls.resetDBBtn.label:SetText(labels.SETTINGS_RESET_DB or "Reset All Settings")
  end
  if controls.resetHint then
    controls.resetHint:SetText(labels.SETTINGS_SECTION_RESET_HINT or "Use these actions to restore the frame or all settings.")
  end

  if controls.betaHeader then
    controls.betaHeader:SetText(labels.SETTINGS_BETA_NOTICE or "Beta")
  end
  if controls.betaNoticeText then
    controls.betaNoticeText:SetText(labels.BETA_NOTICE_TEXT or "This addon is in BETA status. Please report bugs at:")
  end
end
