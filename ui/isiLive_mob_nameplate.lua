local _, addonTable = ...
addonTable = addonTable or {}

local MobNameplate = {}
addonTable.MobNameplate = MobNameplate

local enabled = false
local registered = false
local eventFrame = nil

local frames = {}

local format = {
  showPercent = true,
}

local appearance = {
  fontSize = 12,
  position = "RIGHT",
  xOffset = 0,
  yOffset = 0,
}

local function IsSecretValue(v)
  local fn = rawget(_G, "issecretvalue")
  return type(fn) == "function" and fn(v) == true
end

local function SafeCall(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, a, b, c, d = pcall(fn, ...)
  if not ok then
    return nil
  end
  return a, b, c, d
end

local function IsChallengeModeActive()
  local api = rawget(_G, "C_ChallengeMode")
  if type(api) ~= "table" or type(api.IsChallengeModeActive) ~= "function" then
    return false
  end
  local ok, active = pcall(api.IsChallengeModeActive)
  return ok and active == true
end

local function HasProgressAPI()
  local api = rawget(_G, "C_ScenarioInfo")
  return type(api) == "table" and type(api.GetUnitCriteriaProgressValues) == "function"
end

local function HasNamePlateAPI()
  local api = rawget(_G, "C_NamePlate")
  return type(api) == "table" and type(api.GetNamePlateForUnit) == "function"
end

local function GetNameplate(unit)
  local api = rawget(_G, "C_NamePlate")
  if type(api) ~= "table" or type(api.GetNamePlateForUnit) ~= "function" then
    return nil
  end
  local ok, plate = pcall(api.GetNamePlateForUnit, unit)
  if not ok or type(plate) ~= "table" then
    return nil
  end
  return plate
end

-- Parses a unit GUID and returns the NPC id as a number (nil for players/pets).
-- Secret-Value guarded: the GUID must be type-checked, Secret-checked and
-- non-empty BEFORE `:match` runs, otherwise a tainted GUID taints the stack.
local function NpcIdFromGuid(guid)
  if type(guid) ~= "string" or IsSecretValue(guid) or guid == "" then
    return nil
  end
  local kind, _, _, _, _, npcStr = guid:match("^(%a+)%-(%d+)%-(%d+)%-(%d+)%-(%d+)%-(%d+)%-")
  if kind ~= "Creature" and kind ~= "Vehicle" then
    return nil
  end
  return tonumber(npcStr)
end

-- Computes a mob's forces contribution from the bundled MDT-synced DB
-- (data/isiLive_mplus_forces.lua). Returns (percentString, rawCount) on success
-- or (nil, nil) when the NPC is not tracked / the map has no forces total.
-- This is the source of truth for "what does THIS mob contribute to the key"
-- because Blizzard's GetUnitCriteriaProgressValues(unit) percentString in 12.0+
-- can return the cumulative dungeon progress under some protected paths instead
-- of the per-mob value the criterion was originally designed to expose.
local function ResolveMobContributionFromDB(unit, activeMapID)
  if type(activeMapID) ~= "number" then
    return nil, nil
  end
  local unitGUIDFn = rawget(_G, "UnitGUID")
  if type(unitGUIDFn) ~= "function" then
    return nil, nil
  end
  local okGuid, guid = pcall(unitGUIDFn, unit)
  if not okGuid or type(guid) ~= "string" or IsSecretValue(guid) or guid == "" then
    return nil, nil
  end
  local npcId = NpcIdFromGuid(guid)
  if not npcId then
    return nil, nil
  end
  local db = addonTable.MPlusForces
  if type(db) ~= "table" or type(db.byNpcId) ~= "table" or type(db.dungeonTotal) ~= "table" then
    return nil, nil
  end
  local entry = db.byNpcId[npcId]
  if type(entry) ~= "table" or entry.mapID ~= activeMapID then
    return nil, nil
  end
  local dungeon = db.dungeonTotal[activeMapID]
  local total = dungeon and tonumber(dungeon.total) or 0
  local count = tonumber(entry.count) or 0
  if total <= 0 or count <= 0 then
    return nil, nil
  end
  local percent = (count / total) * 100
  return string.format("%.2f", percent), count
end

local function GetActiveChallengeMapID()
  local api = rawget(_G, "C_ChallengeMode")
  if type(api) ~= "table" or type(api.GetActiveChallengeMapID) ~= "function" then
    return nil
  end
  local ok, mapID = pcall(api.GetActiveChallengeMapID)
  if not ok or type(mapID) ~= "number" or IsSecretValue(mapID) or mapID <= 0 then
    return nil
  end
  return mapID
end

local function IsEligibleUnit(unit)
  local unitExists = rawget(_G, "UnitExists")
  if type(unitExists) ~= "function" then
    return false
  end
  local okExists, exists = pcall(unitExists, unit)
  if not okExists or exists ~= true then
    return false
  end

  local unitGUID = rawget(_G, "UnitGUID")
  if type(unitGUID) ~= "function" then
    return false
  end
  local okGuid, guid = pcall(unitGUID, unit)
  if not okGuid or type(guid) ~= "string" or IsSecretValue(guid) or guid == "" then
    return false
  end

  local unitReaction = rawget(_G, "UnitReaction")
  if type(unitReaction) == "function" then
    local okReact, reaction = pcall(unitReaction, unit, "player")
    if okReact and not IsSecretValue(reaction) and type(reaction) == "number" and reaction > 4 then
      return false
    end
  end

  return true
end

local function BuildText(percentString)
  if
    not format.showPercent
    or type(percentString) ~= "string"
    or IsSecretValue(percentString)
    or percentString == ""
  then
    return nil
  end
  return percentString .. "%"
end

local function ApplyFont(fontString)
  if type(fontString) ~= "table" or type(fontString.SetFont) ~= "function" then
    return
  end
  local file, flags
  local template = rawget(_G, "GameFontNormalOutline")
  if type(template) == "table" and type(template.GetFont) == "function" then
    local ok, f, _, fl = pcall(template.GetFont, template)
    if ok then
      file, flags = f, fl
    end
  end
  if type(file) ~= "string" or file == "" then
    file = "Fonts\\FRIZQT__.TTF"
  end
  if type(flags) ~= "string" or flags == "" then
    flags = "OUTLINE"
  end
  local size = tonumber(appearance.fontSize) or 12
  pcall(fontString.SetFont, fontString, file, size, flags)
end

local function CreateOrGetFrame(unit)
  local frame = frames[unit]
  if frame then
    return frame
  end
  local createFrame = rawget(_G, "CreateFrame")
  if type(createFrame) ~= "function" then
    return nil
  end
  local uiParent = rawget(_G, "UIParent")
  local ok, f = pcall(createFrame, "Frame", nil, uiParent)
  if not ok or type(f) ~= "table" then
    return nil
  end
  f:SetSize(80, 20)
  if f.SetFrameStrata then
    f:SetFrameStrata("MEDIUM")
  end
  if f.SetIgnoreParentAlpha then
    f:SetIgnoreParentAlpha(true)
  end
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalOutline")
  f.text:SetPoint("CENTER")
  if f.text.SetTextColor then
    f.text:SetTextColor(1, 1, 1, 1)
  end
  ApplyFont(f.text)
  frames[unit] = f
  return f
end

local function ApplyPosition(frame, nameplate)
  if not frame or not nameplate then
    return
  end
  frame:ClearAllPoints()
  local pos = appearance.position or "RIGHT"
  local xo = appearance.xOffset or 0
  local yo = appearance.yOffset or 0
  if pos == "RIGHT" then
    frame:SetPoint("LEFT", nameplate, "RIGHT", xo, yo)
  elseif pos == "LEFT" then
    frame:SetPoint("RIGHT", nameplate, "LEFT", xo, yo)
  elseif pos == "TOP" then
    frame:SetPoint("BOTTOM", nameplate, "TOP", xo, yo)
  elseif pos == "BOTTOM" then
    frame:SetPoint("TOP", nameplate, "BOTTOM", xo, yo)
  else
    frame:SetPoint("CENTER", nameplate, "CENTER", xo, yo)
  end
end

local function UpdateNameplate(unit)
  local frame = frames[unit]

  if enabled == false or not HasProgressAPI() or not HasNamePlateAPI() then
    if frame then
      frame:Hide()
    end
    return
  end

  if not IsChallengeModeActive() then
    if frame then
      frame:Hide()
    end
    return
  end

  if not IsEligibleUnit(unit) then
    if frame then
      frame:Hide()
    end
    return
  end

  local activeMapID = GetActiveChallengeMapID()

  -- Primary source: bundled MDT-synced forces DB, which is deterministic and
  -- guaranteed to be the per-mob contribution. Fallback to the Blizzard API
  -- when the NPC is missing from the DB (e.g. freshly added patch mob before
  -- the next scheduled DB refresh).
  local percentString = ResolveMobContributionFromDB(unit, activeMapID)
  if not percentString then
    local api = rawget(_G, "C_ScenarioInfo")
    local _, _, apiPercent = SafeCall(api.GetUnitCriteriaProgressValues, unit)
    if not IsSecretValue(apiPercent) then
      percentString = apiPercent
    end
  end

  local text = BuildText(percentString)
  if not text then
    if frame then
      frame:Hide()
    end
    return
  end

  local nameplate = GetNameplate(unit)
  if not nameplate then
    if frame then
      frame:Hide()
    end
    return
  end

  frame = CreateOrGetFrame(unit)
  if not frame then
    return
  end

  ApplyPosition(frame, nameplate)
  ApplyFont(frame.text)
  if frame.text and frame.text.SetText then
    frame.text:SetText(text)
  end
  frame:Show()
end

local function HideAll()
  for unit, frame in pairs(frames) do
    if frame and frame.Hide then
      frame:Hide()
    end
    frames[unit] = nil
  end
end

local function RefreshAll()
  for i = 1, 40 do
    UpdateNameplate("nameplate" .. i)
  end
end

local function OnEvent(_, event, arg1)
  if event == "NAME_PLATE_UNIT_ADDED" and type(arg1) == "string" then
    UpdateNameplate(arg1)
  elseif event == "NAME_PLATE_UNIT_REMOVED" and type(arg1) == "string" then
    local frame = frames[arg1]
    if frame then
      frame:Hide()
      frames[arg1] = nil
    end
  else
    RefreshAll()
  end
end

local function EnsureEventFrame()
  if eventFrame then
    return eventFrame
  end
  local createFrame = rawget(_G, "CreateFrame")
  if type(createFrame) ~= "function" then
    return nil
  end
  local ok, f = pcall(createFrame, "Frame")
  if not ok or type(f) ~= "table" then
    return nil
  end
  f:SetScript("OnEvent", OnEvent)
  eventFrame = f
  return f
end

local function RegisterEvents()
  local f = EnsureEventFrame()
  if not f or not f.RegisterEvent then
    return false
  end
  f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
  f:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
  f:RegisterEvent("CHALLENGE_MODE_START")
  f:RegisterEvent("PLAYER_ENTERING_WORLD")
  f:RegisterEvent("SCENARIO_UPDATE")
  return true
end

local function UnregisterEvents()
  if not eventFrame or not eventFrame.UnregisterAllEvents then
    return
  end
  eventFrame:UnregisterAllEvents()
end

function MobNameplate.SetEnabled(flag)
  local next = flag ~= false
  if next == enabled and registered then
    return
  end
  enabled = next
  if enabled then
    if RegisterEvents() then
      registered = true
      RefreshAll()
    end
  else
    UnregisterEvents()
    registered = false
    HideAll()
  end
end

function MobNameplate.SetFormat(opts)
  if type(opts) ~= "table" then
    return
  end
  if type(opts.showPercent) == "boolean" then
    format.showPercent = opts.showPercent
  end
  if enabled then
    RefreshAll()
  end
end

function MobNameplate.SetAppearance(opts)
  if type(opts) ~= "table" then
    return
  end
  if type(opts.fontSize) == "number" and opts.fontSize > 0 then
    appearance.fontSize = opts.fontSize
  end
  if type(opts.position) == "string" then
    appearance.position = opts.position
  end
  if type(opts.xOffset) == "number" then
    appearance.xOffset = opts.xOffset
  end
  if type(opts.yOffset) == "number" then
    appearance.yOffset = opts.yOffset
  end
  if enabled then
    RefreshAll()
  end
end

function MobNameplate.Register()
  if registered then
    return true
  end
  if not HasProgressAPI() or not HasNamePlateAPI() then
    return false
  end
  if not enabled then
    return true
  end
  if RegisterEvents() then
    registered = true
    RefreshAll()
    return true
  end
  return false
end

function MobNameplate._Test_GetFrames()
  return frames
end

function MobNameplate._Test_GetState()
  return {
    enabled = enabled,
    registered = registered,
    format = { showPercent = format.showPercent },
    appearance = {
      fontSize = appearance.fontSize,
      position = appearance.position,
      xOffset = appearance.xOffset,
      yOffset = appearance.yOffset,
    },
  }
end

function MobNameplate._Test_UpdateNameplate(unit)
  UpdateNameplate(unit)
end

function MobNameplate._Test_Reset()
  enabled = false
  registered = false
  if eventFrame and eventFrame.UnregisterAllEvents then
    eventFrame:UnregisterAllEvents()
  end
  for unit, frame in pairs(frames) do
    if frame and frame.Hide then
      frame:Hide()
    end
    frames[unit] = nil
  end
  format.showPercent = true
  appearance.fontSize = 12
  appearance.position = "RIGHT"
  appearance.xOffset = 0
  appearance.yOffset = 0
end

return MobNameplate
