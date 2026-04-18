local _, addonTable = ...
addonTable = addonTable or {}

local RI = addonTable._RosterInternal or {}
addonTable._RosterInternal = RI

local ApplyFontStringSize = RI.ApplyFontStringSize
local CD_TRACKER_ROW_HEIGHT = RI.CD_TRACKER_ROW_HEIGHT or 20

local KILLTRACK_ROW_BOTTOM_OFFSET = 12
local CD_TRACKER_FONT_SIZE = 12

local function CreateKillTrackRow(mainFrame)
  local UICommon = addonTable.UICommon or {}
  local row = CreateFrame("Frame", nil, mainFrame)
  row:SetHeight(CD_TRACKER_ROW_HEIGHT)
  row:SetPoint("BOTTOMLEFT", 10, KILLTRACK_ROW_BOTTOM_OFFSET)
  row:SetPoint("BOTTOMRIGHT", -10, KILLTRACK_ROW_BOTTOM_OFFSET)

  local box = CreateFrame("Frame", nil, row, "BackdropTemplate")
  box:SetHeight(CD_TRACKER_ROW_HEIGHT)
  box:SetPoint("LEFT", row, "LEFT", 0, 0)
  box:SetPoint("RIGHT", row, "RIGHT", 0, 0)
  if type(UICommon.ApplyBackdrop) == "function" then
    UICommon.ApplyBackdrop(box, "CD_BOX")
  end

  local label = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("LEFT", box, "LEFT", 6, 0)
  label:SetWidth(84)
  label:SetJustifyH("LEFT")
  label:SetText("|cff888888M+Killtracker|r")
  ApplyFontStringSize(label, CD_TRACKER_FONT_SIZE)

  local pullText = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  pullText:SetPoint("RIGHT", box, "RIGHT", -66, 0)
  pullText:SetWidth(54)
  pullText:SetJustifyH("RIGHT")
  pullText:SetText("")
  ApplyFontStringSize(pullText, CD_TRACKER_FONT_SIZE)

  local barContainer = CreateFrame("Frame", nil, box)
  barContainer:SetPoint("LEFT", box, "LEFT", 94, 0)
  barContainer:SetPoint("RIGHT", box, "RIGHT", -122, 0)
  barContainer:SetHeight(8)

  local barBg = barContainer:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints(barContainer)
  barBg:SetTexture("Interface\\Buttons\\WHITE8X8")
  if type(barBg.SetVertexColor) == "function" then
    barBg:SetVertexColor(0.12, 0.12, 0.12)
  end

  local barFill = barContainer:CreateTexture(nil, "ARTWORK")
  if type(barFill.SetPoint) == "function" then
    barFill:SetPoint("TOPLEFT", barContainer, "TOPLEFT", 0, 0)
    barFill:SetPoint("BOTTOMLEFT", barContainer, "BOTTOMLEFT", 0, 0)
  end
  if type(barFill.SetWidth) == "function" then
    barFill:SetWidth(1)
  end
  if type(barFill.SetTexture) == "function" then
    barFill:SetTexture("Interface\\Buttons\\WHITE8X8")
  end
  if type(barFill.SetVertexColor) == "function" then
    barFill:SetVertexColor(0.2, 0.75, 0.35)
  end
  barFill:Hide()

  local barPull = barContainer:CreateTexture(nil, "ARTWORK")
  if type(barPull.SetPoint) == "function" then
    barPull:SetPoint("TOPLEFT", barFill, "TOPRIGHT", 0, 0)
    barPull:SetPoint("BOTTOMLEFT", barFill, "BOTTOMRIGHT", 0, 0)
  end
  if type(barPull.SetWidth) == "function" then
    barPull:SetWidth(1)
  end
  if type(barPull.SetTexture) == "function" then
    barPull:SetTexture("Interface\\Buttons\\WHITE8X8")
  end
  if type(barPull.SetVertexColor) == "function" then
    barPull:SetVertexColor(0.4, 0.7, 1.0, 0.7)
  end
  barPull:Hide()

  local pctText = box:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  pctText:SetPoint("RIGHT", box, "RIGHT", -6, 0)
  pctText:SetWidth(58)
  pctText:SetJustifyH("RIGHT")
  pctText:SetText("--,--")
  ApplyFontStringSize(pctText, CD_TRACKER_FONT_SIZE)

  row.killTrackBarContainer = barContainer
  row.killTrackBarFill = barFill
  row.killTrackBarPull = barPull
  row.killTrackPctText = pctText
  row.killTrackPullText = pullText
  return row
end

local function UpdateKillTrackRow(row)
  if not row then
    return
  end

  local KillTrack = addonTable.KillTrack
  local data = type(KillTrack) == "table" and type(KillTrack.GetData) == "function" and KillTrack.GetData() or nil

  local barContainer = row.killTrackBarContainer
  local barFill = row.killTrackBarFill
  local barPull = row.killTrackBarPull
  local pctText = row.killTrackPctText
  local pullText = row.killTrackPullText

  if data and data.active then
    local pct = math.max(0, math.min(data.percent, 100))
    local r, g, b
    if pct < 80 then
      r, g, b = 0.2, 0.75, 0.35
    elseif pct < 95 then
      r, g, b = 0.9, 0.75, 0.1
    else
      r, g, b = 0.9, 0.3, 0.15
    end
    local w = type(barContainer.GetWidth) == "function" and barContainer:GetWidth() or 0
    if barFill then
      local fw = math.floor(w * pct / 100 + 0.5)
      if fw > 0 then
        barFill:SetWidth(fw)
        barFill:SetVertexColor(r, g, b)
        barFill:Show()
      else
        barFill:Hide()
      end
    end
    local pullPct = (data.inCombat and type(data.pullPercent) == "number") and data.pullPercent or 0
    if barPull then
      if data.inCombat and pullPct > 0 and w > 0 then
        local pw = math.floor(w * pullPct / 100 + 0.5)
        local fw = barFill and (type(barFill.GetWidth) == "function" and barFill:GetWidth() or 0) or 0
        if fw + pw > w then
          pw = math.max(1, w - fw)
        end
        barPull:SetWidth(math.max(1, pw))
        barPull:Show()
      else
        barPull:Hide()
      end
    end
    if pctText then
      pctText:SetText(string.format("%.2f%%", pct):gsub("%.", ","))
      if type(pctText.SetTextColor) == "function" then
        pctText:SetTextColor(r, g, b)
      end
    end
    if pullText then
      if data.inCombat and pullPct > 0 then
        pullText:SetText("+" .. string.format("%.2f%%", pullPct):gsub("%.", ","))
        if type(pullText.SetTextColor) == "function" then
          pullText:SetTextColor(0.6, 0.85, 1.0)
        end
      else
        pullText:SetText("")
      end
    end
  else
    if barFill then
      barFill:Hide()
    end
    if barPull then
      barPull:Hide()
    end
    if pctText then
      pctText:SetText("--,--")
      if type(pctText.SetTextColor) == "function" then
        pctText:SetTextColor(0.4, 0.4, 0.5)
      end
    end
    if pullText then
      pullText:SetText("")
    end
  end
end

RI.CreateKillTrackRow = CreateKillTrackRow
RI.UpdateKillTrackRow = UpdateKillTrackRow
