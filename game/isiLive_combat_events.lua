local _, addonTable = ...
addonTable = addonTable or {}

local CombatEvents = {}
addonTable.CombatEvents = CombatEvents

-- Battle-Res spells a player can cast on a dead ally in combat.
local BR_SPELL_IDS = {
  [20484] = true, -- Rebirth (Druid)
  [61999] = true, -- Raise Ally (Death Knight)
  [391054] = true, -- Intercession (Paladin)
  [20707] = true, -- Soulstone Resurrection (Warlock)
}

-- Bloodlust / Heroism / Time Warp variant cast spell IDs. UNIT_SPELLCAST_SUCCEEDED
-- fires exactly once per completed cast, so only the cast-triggering IDs belong
-- here (the corresponding Sated / Exhaustion debuffs never produce a cast event).
local LUST_CAST_IDS = {
  [2825] = true, -- Bloodlust (Shaman)
  [32182] = true, -- Heroism (Shaman)
  [80353] = true, -- Time Warp (Mage)
  [264667] = true, -- Primal Rage (Hunter Ferocity Pet)
  [390386] = true, -- Fury of the Aspects (Evoker)
  [381301] = true, -- Feral Hide Drums
  [178207] = true, -- Drums of Fury
  [230935] = true, -- Drums of the Mountain
  [256740] = true, -- Drums of the Maelstrom
  [292463] = true, -- Drums of Deathly Ferocity
  [90355] = true, -- Ancient Hysteria (Core Hound)
  [160452] = true, -- Netherwinds (Nether Ray Pet)
}

local DEDUP_WINDOW_SECONDS = 3

local function DefaultGetTime()
  local fn = rawget(_G, "GetTime")
  return type(fn) == "function" and fn() or 0
end

local function DefaultIsInKey()
  local api = rawget(_G, "C_ChallengeMode")
  if type(api) ~= "table" or type(api.GetActiveChallengeMapID) ~= "function" then
    return false
  end
  local ok, mapID = pcall(api.GetActiveChallengeMapID)
  if not ok then
    return false
  end
  return type(mapID) == "number" and mapID > 0
end

-- Resolves a unit token (e.g. "party2") to a display-ready name. Prefers
-- GetUnitName(unit, true) so cross-realm players keep their realm suffix.
local function BuildDefaultGetUnitName()
  return function(unit)
    local getUnitNameFn = rawget(_G, "GetUnitName")
    if type(getUnitNameFn) == "function" then
      local ok, name = pcall(getUnitNameFn, unit, true)
      if ok and type(name) == "string" and name ~= "" then
        return name
      end
    end
    local unitNameFn = rawget(_G, "UnitName")
    if type(unitNameFn) == "function" then
      local ok, name = pcall(unitNameFn, unit)
      if ok and type(name) == "string" and name ~= "" then
        return name
      end
    end
    return unit
  end
end

-- Strips the "-Realm" suffix from names so the chat message reads naturally on
-- the local realm. Cross-realm names keep the realm segment.
local function FormatDisplayName(name)
  if type(name) ~= "string" or name == "" then
    return "?"
  end
  local dash = string.find(name, "-", 1, true)
  if not dash then
    return name
  end
  return string.sub(name, 1, dash - 1)
end

-- Resolves the chat channel for group announcements. INSTANCE_CHAT wins
-- inside M+ / raid instances because PARTY/RAID do not route there.
local function DefaultResolveChannel()
  local inInstanceGroup = rawget(_G, "IsInGroup")
  local partyCategoryInstance = rawget(_G, "LE_PARTY_CATEGORY_INSTANCE")
  if type(inInstanceGroup) == "function" and partyCategoryInstance ~= nil then
    local ok, inInstance = pcall(inInstanceGroup, partyCategoryInstance)
    if ok and inInstance then
      return "INSTANCE_CHAT"
    end
  end
  local inRaid = rawget(_G, "IsInRaid")
  if type(inRaid) == "function" then
    local ok, isRaid = pcall(inRaid)
    if ok and isRaid then
      return "RAID"
    end
  end
  if type(inInstanceGroup) == "function" then
    local ok, isGroup = pcall(inInstanceGroup)
    if ok and isGroup then
      return "PARTY"
    end
  end
  return nil
end

local function DefaultSendChat(msg)
  local sendChatMessage = rawget(_G, "SendChatMessage")
  if type(sendChatMessage) ~= "function" then
    return
  end
  local channel = DefaultResolveChannel()
  if not channel then
    return
  end
  pcall(sendChatMessage, tostring(msg), channel)
end

function CombatEvents.CreateController(opts)
  opts = opts or {}
  local getTime = type(opts.getTime) == "function" and opts.getTime or DefaultGetTime
  local isInKey = type(opts.isInKey) == "function" and opts.isInKey or DefaultIsInKey
  local getUnitName = type(opts.getUnitName) == "function" and opts.getUnitName or BuildDefaultGetUnitName()
  local sendChat = type(opts.sendChat) == "function" and opts.sendChat or DefaultSendChat
  local getL = type(opts.getL) == "function" and opts.getL or function()
    return {}
  end
  local getDB = type(opts.getDB) == "function" and opts.getDB or function()
    return {}
  end

  local controller = {}
  local recent = {}

  local function IsEnabledForBR()
    local db = getDB() or {}
    return db.chatAnnounceBR ~= false
  end

  local function IsEnabledForLust()
    local db = getDB() or {}
    return db.chatAnnounceLust ~= false
  end

  local function ShouldDedup(sourceName, spellID)
    if type(sourceName) ~= "string" or sourceName == "" or type(spellID) ~= "number" then
      return false
    end
    local key = sourceName .. "|" .. spellID
    local now = getTime()
    local last = recent[key]
    if last and (now - last) < DEDUP_WINDOW_SECONDS then
      return true
    end
    recent[key] = now
    return false
  end

  local function AnnounceBR(sourceName, spellID)
    if ShouldDedup(sourceName or "", spellID) then
      return
    end
    local L = getL() or {}
    local template = L.COMBAT_CHAT_BR_USED or "%s used BR"
    sendChat(string.format(template, FormatDisplayName(sourceName)))
  end

  local function AnnounceLust(sourceName, spellID)
    if ShouldDedup(sourceName or "", spellID) then
      return
    end
    local L = getL() or {}
    local template = L.COMBAT_CHAT_LUST_STARTED or "%s started Bloodlust"
    sendChat(string.format(template, FormatDisplayName(sourceName)))
  end

  -- Only self-casts: the 12.0.0 Secret Values system masks spellID for other
  -- players' UNIT_SPELLCAST_SUCCEEDED events inside M+ / boss restriction
  -- zones, which makes BR_SPELL_IDS[spellID] throw "table index is secret".
  -- Each isiLive client detects exactly its own cast and broadcasts the
  -- announcement to group chat, so N isiLive users cover all N casters.
  function controller.HandleUnitSpellcastSucceeded(unit, _, spellID)
    if unit ~= "player" then
      return
    end
    if not isInKey() then
      return
    end
    if type(spellID) ~= "number" then
      return
    end
    if BR_SPELL_IDS[spellID] then
      if not IsEnabledForBR() then
        return
      end
      AnnounceBR(getUnitName(unit), spellID)
      return
    end
    if LUST_CAST_IDS[spellID] then
      if not IsEnabledForLust() then
        return
      end
      AnnounceLust(getUnitName(unit), spellID)
    end
  end

  function controller.Reset()
    recent = {}
  end

  return controller
end

-- Event frame: bound on file load so the module self-installs. The factory
-- wires getL/getDB/print through CombatEvents.SetDependencies().
--
-- COMBAT_LOG_EVENT_UNFILTERED was removed from the public addon API in patch
-- 12.0.0 (Midnight) and raises ADDON_ACTION_FORBIDDEN on every
-- RegisterEvent() attempt, so we listen to UNIT_SPELLCAST_SUCCEEDED instead.
-- That event is not taint-sensitive, fires once per completed cast, and
-- exposes enough info (unit token + spell ID) to announce BR / Bloodlust
-- without needing combat-log access.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
eventFrame:RegisterEvent("CHALLENGE_MODE_START")
eventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")

local controllerInstance = nil

function CombatEvents.SetDependencies(deps)
  if type(deps) ~= "table" then
    return
  end
  controllerInstance = CombatEvents.CreateController(deps)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if not controllerInstance then
    return
  end
  if event == "UNIT_SPELLCAST_SUCCEEDED" then
    controllerInstance.HandleUnitSpellcastSucceeded(...)
    return
  end
  if event == "CHALLENGE_MODE_START" or event == "CHALLENGE_MODE_COMPLETED" then
    controllerInstance.Reset()
  end
end)
