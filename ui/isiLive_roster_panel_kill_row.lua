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
  label:SetText("|cff888888M+Killtracker|r") -- i18n-ok: brand name, kept across all locales
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

  -- Boss-target markers: thin vertical lines on the bar at each cumulative
  -- boss-target threshold from data/isiLive_mplus_boss_targets.lua. Pre-allocate
  -- a fixed pool of 8 (current Midnight S1 dungeons have 3-4 bosses each, 8 is
  -- safe headroom for future seasons). Visibility / position / color is set
  -- per render in UpdateKillTrackRow.
  local bossMarkers = {}
  for i = 1, 8 do
    local marker = barContainer:CreateTexture(nil, "OVERLAY")
    if type(marker.SetTexture) == "function" then
      marker:SetTexture("Interface\\Buttons\\WHITE8X8")
    end
    if type(marker.SetWidth) == "function" then
      marker:SetWidth(1)
    end
    if type(marker.Hide) == "function" then
      marker:Hide()
    end
    bossMarkers[i] = marker
  end

  row.killTrackBarContainer = barContainer
  row.killTrackBarFill = barFill
  row.killTrackBarPull = barPull
  row.killTrackPctText = pctText
  row.killTrackPullText = pullText
  row.killTrackBossMarkers = bossMarkers
  return row
end

local function ResolveBossTargetsForMap(mapID)
  if type(mapID) ~= "number" then
    return nil
  end
  local db = rawget(_G, "IsiLiveDB")
  if type(db) == "table" and type(db.bossTargetsOverride) == "table" then
    local override = db.bossTargetsOverride[mapID]
    if type(override) == "table" and #override > 0 then
      return override
    end
  end
  local defaults = addonTable.MPlusBossTargets
  if type(defaults) ~= "table" or type(defaults.byMapID) ~= "table" then
    return nil
  end
  local entry = defaults.byMapID[mapID]
  if type(entry) == "table" and #entry > 0 then
    return entry
  end
  return nil
end

local function UpdateBossTargetMarkers(row, data, barContainer, containerWidth)
  local bossMarkers = row.killTrackBossMarkers
  if type(bossMarkers) ~= "table" then
    return
  end

  -- Always hide all markers first; we re-show only the ones that match the
  -- current map. Avoids stale markers when switching dungeons mid-session.
  for i = 1, #bossMarkers do
    local m = bossMarkers[i]
    if m and type(m.Hide) == "function" then
      m:Hide()
    end
  end

  if not data or not data.active or not barContainer or containerWidth <= 0 then
    return
  end

  local targets = ResolveBossTargetsForMap(data.mapID)
  if not targets then
    return
  end

  local cumulative = math.max(0, math.min(data.percent or 0, 100))
  local pull = (data.inCombat and type(data.pullPercent) == "number") and data.pullPercent or 0
  local cumulativePlusPull = math.min(cumulative + pull, 100)

  for i, targetPct in ipairs(targets) do
    local marker = bossMarkers[i]
    if not marker then
      break
    end
    local target = tonumber(targetPct)
    if target and target > 0 and target <= 100 then
      local x = math.floor(containerWidth * target / 100 + 0.5)
      if type(marker.ClearAllPoints) == "function" then
        marker:ClearAllPoints()
      end
      if type(marker.SetPoint) == "function" then
        marker:SetPoint("TOP", barContainer, "TOPLEFT", x, 0)
        marker:SetPoint("BOTTOM", barContainer, "BOTTOMLEFT", x, 0)
      end
      local r, g, b
      if cumulative >= target then
        -- Boss-threshold already cleared by accumulated forces.
        r, g, b = 0.2, 0.85, 0.3
      elseif cumulativePlusPull >= target then
        -- Current pull will clear the threshold once it lands.
        r, g, b = 1.0, 0.85, 0.2
      else
        -- Not yet reachable from this pull.
        r, g, b = 0.6, 0.6, 0.65
      end
      if type(marker.SetVertexColor) == "function" then
        marker:SetVertexColor(r, g, b, 0.9)
      end
      if type(marker.Show) == "function" then
        marker:Show()
      end
    end
  end
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
    UpdateBossTargetMarkers(row, data, barContainer, w)
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
    UpdateBossTargetMarkers(row, nil, barContainer, 0)
  end
end

RI.CreateKillTrackRow = CreateKillTrackRow
RI.UpdateKillTrackRow = UpdateKillTrackRow
