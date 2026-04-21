local _, addonTable = ...
addonTable = addonTable or {}

local MobTooltip = {}
addonTable.MobTooltip = MobTooltip

local enabled = true
local registered = false

-- Prevents stacking the same line on tooltip rerenders (TooltipDataProcessor
-- fires on every refresh, including hover-over-self reflow).
local lastAppendedKey = {}

local function IsSecretValue(v)
  local fn = rawget(_G, "issecretvalue")
  return type(fn) == "function" and fn(v) == true
end

local function GetForcesDB()
  local db = addonTable.MPlusForces
  if type(db) ~= "table" then
    return nil
  end
  if type(db.byNpcId) ~= "table" or type(db.dungeonTotal) ~= "table" then
    return nil
  end
  return db
end

local function GetActiveChallengeMapID()
  local api = rawget(_G, "C_ChallengeMode")
  if type(api) ~= "table" or type(api.GetActiveChallengeMapID) ~= "function" then
    return nil
  end
  local issecret = rawget(_G, "issecretvalue") or function()
    return false
  end
  local ok, mapID = pcall(api.GetActiveChallengeMapID)
  if not ok or type(mapID) ~= "number" or mapID <= 0 or issecret(mapID) then
    return nil
  end
  return mapID
end

-- Returns npcID as a number, or nil if the GUID is not a Creature/Vehicle.
local function NpcIdFromGuid(guid)
  if type(guid) ~= "string" or guid == "" then
    return nil
  end
  local kind, _, _, _, _, npcStr = guid:match("^(%a+)%-(%d+)%-(%d+)%-(%d+)%-(%d+)%-(%d+)%-")
  if kind ~= "Creature" and kind ~= "Vehicle" then
    return nil
  end
  return tonumber(npcStr)
end

local function ResolveGuid(tooltipData)
  if type(tooltipData) == "table" then
    local candidate = tooltipData.guid
    if type(candidate) == "string" and not IsSecretValue(candidate) and candidate ~= "" then
      return candidate
    end
  end
  local unitGUIDFn = rawget(_G, "UnitGUID")
  if type(unitGUIDFn) ~= "function" then
    return nil
  end
  local ok, guid = pcall(unitGUIDFn, "mouseover")
  if ok and type(guid) == "string" and not IsSecretValue(guid) and guid ~= "" then
    return guid
  end
  return nil
end

local function AppendForcesLine(tooltip, data)
  if enabled == false then
    return
  end
  if type(tooltip) ~= "table" or type(tooltip.AddLine) ~= "function" then
    return
  end

  local activeMapID = GetActiveChallengeMapID()
  if not activeMapID then
    return
  end

  local db = GetForcesDB()
  if not db then
    return
  end

  local guid = ResolveGuid(data)
  local npcId = NpcIdFromGuid(guid)
  if not npcId then
    return
  end

  local entry = db.byNpcId[npcId]
  if type(entry) ~= "table" or entry.mapID ~= activeMapID then
    return
  end

  local dungeon = db.dungeonTotal[activeMapID]
  local total = dungeon and tonumber(dungeon.total) or 0
  local count = tonumber(entry.count) or 0
  if total <= 0 or count <= 0 then
    return
  end

  local percent = (count / total) * 100
  local key = tostring(guid) .. ":" .. tostring(npcId)
  if lastAppendedKey[tooltip] == key then
    return
  end
  lastAppendedKey[tooltip] = key

  tooltip:AddLine(string.format("Forces: %.2f%% (+%d)", percent, count), 0.4, 0.8, 1)
end

local function HookTooltipClear()
  local gameTooltip = rawget(_G, "GameTooltip")
  if type(gameTooltip) ~= "table" or type(gameTooltip.HookScript) ~= "function" then
    return
  end
  gameTooltip:HookScript("OnTooltipCleared", function(self)
    lastAppendedKey[self] = nil
  end)
end

function MobTooltip.SetEnabled(flag)
  enabled = flag ~= false
end

function MobTooltip.Register()
  if registered then
    return true
  end

  local tdp = rawget(_G, "TooltipDataProcessor")
  local enumRef = rawget(_G, "Enum")
  local dataType = type(enumRef) == "table" and enumRef.TooltipDataType or nil
  if
    type(tdp) ~= "table"
    or type(tdp.AddTooltipPostCall) ~= "function"
    or type(dataType) ~= "table"
    or dataType.Unit == nil
  then
    return false
  end

  tdp.AddTooltipPostCall(dataType.Unit, function(self, data)
    AppendForcesLine(self, data)
  end)

  HookTooltipClear()
  registered = true
  return true
end

return MobTooltip
