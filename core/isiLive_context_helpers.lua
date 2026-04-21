local _, addonTable = ...

addonTable = addonTable or {}

local ContextHelpers = {}
addonTable.ContextHelpers = ContextHelpers

function ContextHelpers.GetAddonVersionRaw(addonName)
  local legacyGetAddOnMetadata = rawget(_G, "GetAddOnMetadata")
  local version = nil
  if C_AddOns and C_AddOns.GetAddOnMetadata then
    version = C_AddOns.GetAddOnMetadata(addonName, "Version")
  elseif legacyGetAddOnMetadata then
    version = legacyGetAddOnMetadata(addonName, "Version")
  end
  return tostring(version or "?")
end

function ContextHelpers.CreateRealmInfoGetter()
  local realmInfoLib
  return function()
    if realmInfoLib ~= nil then
      return realmInfoLib
    end
    if LibStub and LibStub.GetLibrary then
      realmInfoLib = LibStub:GetLibrary("LibRealmInfo", true)
    else
      realmInfoLib = false
    end
    return realmInfoLib
  end
end

function ContextHelpers.GetUnitServerLanguage(isiLiveLocale, getRealmInfoLib, unit, realm)
  return isiLiveLocale.GetUnitServerLanguage(unit, realm, getRealmInfoLib)
end

function ContextHelpers.BuildDummyRoster(opts)
  return opts.demoBuildDummyRoster({
    previewVariant = opts.previewVariant,
    includeGhostMember = opts.includeGhostMember,
    getUnitNameAndRealm = opts.getUnitNameAndRealm,
    getUnitClass = opts.getUnitClass,
    getUnitServerLanguage = opts.getUnitServerLanguage,
    getUnitRole = opts.getUnitRole,
    getPlayerSpecName = opts.getPlayerSpecName,
    getUnitRio = opts.getUnitRio,
  })
end

function ContextHelpers.BuildKeystoneChatLink(mapID, level)
  local numericMapID = math.floor(tonumber(mapID) or 0)
  local numericLevel = math.floor(tonumber(level) or 0)
  if numericMapID <= 0 or numericLevel <= 0 then
    return nil
  end

  local mythicPlusApi = rawget(_G, "C_MythicPlus")
  if mythicPlusApi and type(mythicPlusApi.GetOwnedKeystoneLink) == "function" then
    local okLink, ownedLink = pcall(mythicPlusApi.GetOwnedKeystoneLink)
    if okLink and type(ownedLink) == "string" and ownedLink ~= "" and ownedLink:find("|Hkeystone:", 1, true) then
      return ownedLink
    end
  end

  -- Fallback: GetOwnedKeystoneLink was removed in recent WoW retail.
  -- Scan bags for the Mythic Keystone item (itemID 180653) and return its real link —
  -- manually constructed |Hkeystone:...|h links are silently dropped by the chat server.
  local containerApi = rawget(_G, "C_Container")
  if
    containerApi
    and type(containerApi.GetContainerNumSlots) == "function"
    and type(containerApi.GetContainerItemID) == "function"
    and type(containerApi.GetContainerItemLink) == "function"
  then
    for bagID = 0, 5 do
      local okSlots, numSlots = pcall(containerApi.GetContainerNumSlots, bagID)
      if okSlots and type(numSlots) == "number" and numSlots > 0 then
        for slotID = 1, numSlots do
          local okID, itemID = pcall(containerApi.GetContainerItemID, bagID, slotID)
          if okID and itemID == 180653 then
            local okBagLink, bagLink = pcall(containerApi.GetContainerItemLink, bagID, slotID)
            if okBagLink and type(bagLink) == "string" and bagLink:find("|Hkeystone:", 1, true) then
              return bagLink
            end
          end
        end
      end
    end
  end

  local dungeonName = nil
  if C_ChallengeMode and type(C_ChallengeMode.GetMapUIInfo) == "function" then
    local okName, localizedName = pcall(C_ChallengeMode.GetMapUIInfo, numericMapID)
    if okName and type(localizedName) == "string" and localizedName ~= "" then
      dungeonName = localizedName
    end
  end

  local dungeonLabel = dungeonName and string.format("Keystone: %s +%d", dungeonName, numericLevel)
    or string.format("Keystone +%d", numericLevel)
  -- Plain-text fallback: WoW drops addon-sent chat messages that contain |c...|r color codes
  -- wrapping square brackets — the server treats them as fake item links. Send without color.
  return string.format("[%s]", dungeonLabel)
end

local function ResolveOwnedKeystoneSnapshot(opts)
  opts = opts or {}

  local getOwnedKeystoneSnapshot = type(opts.getOwnedKeystoneSnapshot) == "function" and opts.getOwnedKeystoneSnapshot
    or nil
  if getOwnedKeystoneSnapshot then
    local mapID, level = getOwnedKeystoneSnapshot()
    local numericMapID = tonumber(mapID)
    local numericLevel = tonumber(level)
    if numericMapID and numericMapID > 0 and numericLevel and numericLevel > 0 then
      return math.floor(numericMapID), math.floor(numericLevel)
    end
  end

  local getRoster = type(opts.getRoster) == "function" and opts.getRoster or nil
  if getRoster then
    local roster = getRoster()
    local playerInfo = type(roster) == "table" and roster.player or nil
    local numericMapID = tonumber(playerInfo and playerInfo.keyMapID)
    local numericLevel = tonumber(playerInfo and playerInfo.keyLevel)
    if numericMapID and numericMapID > 0 and numericLevel and numericLevel > 0 then
      return math.floor(numericMapID), math.floor(numericLevel)
    end
  end

  return nil, nil
end

function ContextHelpers.BuildOwnKeystoneAnnounceLine(opts)
  opts = opts or {}

  local keyMapID, keyLevel = ResolveOwnedKeystoneSnapshot(opts)
  if not keyMapID or not keyLevel then
    return nil
  end

  local keyLink = ContextHelpers.BuildKeystoneChatLink(keyMapID, keyLevel)
  if not keyLink then
    local shortCode = type(opts.getDungeonShortCode) == "function" and opts.getDungeonShortCode(keyMapID) or nil
    keyLink = shortCode and string.format("%s +%d", tostring(shortCode), keyLevel)
      or string.format("Keystone +%d", keyLevel)
  end

  local L = type(opts.getL) == "function" and opts.getL() or {}
  local announcePrefix = tostring(L.ANNOUNCE_PREFIX or "PartyKeys:"):gsub("%s+", "")
  return string.format("[isiLive] %s %s", announcePrefix, keyLink)
end

-- Returns the correct chat channel for the current group context.
-- Instance groups (M+, LFG, dungeon finder) must use INSTANCE_CHAT — SendChatMessage
-- silently drops PARTY messages when the player is in an instance group.
function ContextHelpers.ResolveGroupChatChannel()
  local isInGroup = rawget(_G, "IsInGroup")
  if type(isInGroup) ~= "function" then
    return "PARTY"
  end
  local instanceCategory = rawget(_G, "LE_PARTY_CATEGORY_INSTANCE") or 2
  local okInstance, inInstance = pcall(isInGroup, instanceCategory)
  if okInstance and inInstance then
    return "INSTANCE_CHAT"
  end
  return "PARTY"
end

function ContextHelpers.SendPartyChatMessage(message)
  if type(message) ~= "string" or message == "" then
    return false
  end

  local channel = ContextHelpers.ResolveGroupChatChannel()

  local sendChatMessage = rawget(_G, "SendChatMessage")
  if type(sendChatMessage) == "function" then
    local ok = pcall(sendChatMessage, message, channel)
    if ok then
      return true
    end
  end

  local chatInfo = rawget(_G, "C_ChatInfo")
  local sendChatMessageCompat = type(chatInfo) == "table" and chatInfo.SendChatMessage or nil
  if type(sendChatMessageCompat) == "function" then
    local ok = pcall(sendChatMessageCompat, message, channel)
    if ok then
      return true
    end
  end

  return false
end
