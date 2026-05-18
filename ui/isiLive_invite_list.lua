local _, addonTable = ...

addonTable = addonTable or {}

local InviteList = {}
addonTable.InviteList = InviteList

local MAX_ROWS = 5
local ROW_HEIGHT = 52
local FRAME_WIDTH = 560

local function ApplyBackdrop(frame)
  local UICommon = addonTable and addonTable.UICommon
  if type(UICommon) == "table" and type(UICommon.ApplyBackdrop) == "function" then
    if UICommon.ApplyBackdrop(frame, "NOTICE") then
      return
    end
  end
  if type(frame.CreateTexture) == "function" then
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.08, 0.78)
  end
end

local function CreateText(parent, template, justify)
  local text = parent:CreateFontString(nil, "OVERLAY", template or "GameFontNormal")
  text:SetJustifyH(justify or "LEFT")
  text:SetJustifyV("TOP")
  text:SetWordWrap(false)
  if text.SetNonSpaceWrap then
    text:SetNonSpaceWrap(false)
  end
  return text
end

local function GetAnchor(parent)
  local lfgListInviteDialog = rawget(_G, "LFGListInviteDialog")
  if lfgListInviteDialog and type(lfgListInviteDialog.IsShown) == "function" and lfgListInviteDialog:IsShown() then
    return lfgListInviteDialog
  end
  for index = 1, 4 do
    local popup = rawget(_G, "StaticPopup" .. index)
    if popup and type(popup.IsShown) == "function" and popup:IsShown() then
      return popup
    end
  end
  return parent
end

local function RoleLabel(L, role)
  if role == "TANK" then
    return L.ROLE_NAME_TANK or "Tank"
  end
  if role == "HEALER" then
    return L.ROLE_NAME_HEALER or "Healer"
  end
  if role == "DAMAGER" then
    return L.ROLE_NAME_DAMAGE or "Damage"
  end
  return nil
end

local function LevelLabel(entry)
  local level = tonumber(entry.level)
  if level and level > 0 then
    return string.format("+%d", math.floor(level))
  end
  if type(entry.levelText) == "string" and entry.levelText ~= "" then
    return entry.levelText
  end
  return nil
end

local function BuildPrimaryText(entry)
  local dungeon = type(entry.dungeonName) == "string" and entry.dungeonName ~= "" and entry.dungeonName or nil
  local level = LevelLabel(entry)
  if dungeon and level then
    return dungeon .. " " .. level
  end
  return dungeon
    or level
    or (type(entry.groupName) == "string" and entry.groupName ~= "" and entry.groupName)
    or "LFG invite"
end

local function CreateRow(parent, index, callbacks)
  local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  row:SetSize(FRAME_WIDTH - 20, ROW_HEIGHT)
  row:SetPoint("TOPLEFT", parent, "TOPLEFT", 10, -34 - ((index - 1) * (ROW_HEIGHT + 4)))
  row:Hide()

  if type(row.CreateTexture) == "function" then
    row.bg = row:CreateTexture(nil, "BACKGROUND")
    row.bg:SetAllPoints()
    row.bg:SetColorTexture(0.02, 0.02, 0.025, 0.55)
  end

  row.primary = CreateText(row, "GameFontNormal", "LEFT")
  row.primary:SetPoint("TOPLEFT", row, "TOPLEFT", 8, -6)
  row.primary:SetWidth(300)
  row.primary:SetTextColor(1, 0.82, 0.25)

  row.meta = CreateText(row, "GameFontHighlightSmall", "LEFT")
  row.meta:SetPoint("TOPLEFT", row.primary, "BOTTOMLEFT", 0, -2)
  row.meta:SetWidth(300)
  row.meta:SetTextColor(0.86, 0.86, 0.82)

  row.comment = CreateText(row, "GameFontDisableSmall", "LEFT")
  row.comment:SetPoint("TOPLEFT", row.meta, "BOTTOMLEFT", 0, -2)
  row.comment:SetWidth(300)
  row.comment:SetTextColor(0.7, 0.7, 0.7)

  row.accept = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.accept:SetSize(82, 24)
  row.accept:SetPoint("RIGHT", row, "RIGHT", -94, 0)

  row.decline = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  row.decline:SetSize(82, 24)
  row.decline:SetPoint("RIGHT", row, "RIGHT", -6, 0)

  row.accept:SetScript("OnClick", function(self)
    if self.searchResultID and type(callbacks.onAccept) == "function" then
      callbacks.onAccept(self.searchResultID)
    end
  end)
  row.decline:SetScript("OnClick", function(self)
    if self.searchResultID and type(callbacks.onDecline) == "function" then
      callbacks.onDecline(self.searchResultID)
    end
  end)

  return row
end

function InviteList.Create(opts)
  opts = opts or {}
  local parent = opts.parent or UIParent
  local getL = type(opts.getL) == "function" and opts.getL or function()
    return {}
  end
  local isEnabled = type(opts.isEnabled) == "function" and opts.isEnabled or function()
    return true
  end
  local frame = CreateFrame("Frame", "isiLiveInviteListFrame", parent, "BackdropTemplate")
  frame:SetSize(FRAME_WIDTH, 46 + (MAX_ROWS * (ROW_HEIGHT + 4)))
  frame:SetFrameStrata("DIALOG")
  frame:Hide()
  frame:EnableMouse(true)
  ApplyBackdrop(frame)

  local title = CreateText(frame, "GameFontNormalLarge", "LEFT")
  title:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
  title:SetTextColor(1, 0.82, 0.25)

  local rows = {}
  for index = 1, MAX_ROWS do
    rows[index] = CreateRow(frame, index, {
      onAccept = opts.onAccept,
      onDecline = opts.onDecline,
    })
  end

  local state = { invites = {} }

  local function Position()
    frame:ClearAllPoints()
    local anchor = GetAnchor(parent)
    if anchor == parent then
      frame:SetPoint("TOP", parent, "TOP", 0, -220)
    else
      frame:SetPoint("TOP", anchor, "BOTTOM", 0, -8)
    end
  end

  local function Render(invites)
    state.invites = invites or {}
    if isEnabled() == false then
      frame:Hide()
      return
    end
    local L = getL() or {}
    title:SetText(L.INVITE_LIST_TITLE or "Open LFG invites")
    for index, row in ipairs(rows) do
      local entry = state.invites[index]
      if entry then
        local role = RoleLabel(L, entry.role)
        local metaParts = {}
        if type(entry.groupName) == "string" and entry.groupName ~= "" then
          metaParts[#metaParts + 1] = entry.groupName
        end
        if role then
          metaParts[#metaParts + 1] = string.format(L.INVITE_LIST_ROLE_FMT or "Role: %s", role)
        end
        local comment = type(entry.comment) == "string" and entry.comment ~= "" and entry.comment or ""
        row.primary:SetText(BuildPrimaryText(entry))
        row.meta:SetText(table.concat(metaParts, "  |  "))
        row.comment:SetText(comment)
        row.accept:SetText(L.INVITE_LIST_ACCEPT or "Accept")
        row.decline:SetText(L.INVITE_LIST_DECLINE or "Decline")
        row.accept.searchResultID = entry.searchResultID
        row.decline.searchResultID = entry.searchResultID
        row:Show()
      else
        row.accept.searchResultID = nil
        row.decline.searchResultID = nil
        row:Hide()
      end
    end
    frame:SetHeight(46 + (math.min(#state.invites, MAX_ROWS) * (ROW_HEIGHT + 4)))
    if #state.invites > 0 then
      Position()
      frame:Show()
    else
      frame:Hide()
    end
  end

  frame:SetScript("OnUpdate", function(_, elapsed)
    frame._positionElapsed = (frame._positionElapsed or 0) + (elapsed or 0)
    if frame._positionElapsed >= 0.2 then
      frame._positionElapsed = 0
      Position()
    end
  end)

  return {
    frame = frame,
    Render = Render,
    Position = Position,
  }
end
