local _, addonTable = ...

addonTable = addonTable or {}

local Invites = {}
addonTable.Invites = Invites

local unpack = rawget(_G, "unpack") or rawget(table, "unpack")

local OPEN_INVITE_STATUSES = {
  invited = true,
}

local CLOSED_INVITE_STATUSES = {
  inviteaccepted = true,
  accepted = true,
  declined = true,
  invitedeclined = true,
  declined_full = true,
  declined_delisted = true,
  cancelled = true,
  canceled = true,
  failed = true,
  timedout = true,
  timeout = true,
  none = true,
}

local VALID_ROLES = {
  TANK = true,
  HEALER = true,
  DAMAGER = true,
}

local function NormalizeStatus(status)
  if type(status) ~= "string" then
    return nil
  end
  status = string.lower(status)
  if status == "" then
    return nil
  end
  return status
end

local function NormalizeID(value)
  local numeric = tonumber(value)
  if not numeric or numeric <= 0 then
    return nil
  end
  return math.floor(numeric)
end

local function CopyEntry(entry)
  local copy = {}
  for key, value in pairs(entry or {}) do
    copy[key] = value
  end
  return copy
end

local function ParseTitleKeyLevel(title)
  if type(title) ~= "string" or title == "" then
    return nil
  end
  local best = nil
  for digits in string.gmatch(title, "%+[^%a%d]-(%d+)") do
    local n = tonumber(digits)
    if n and n >= 1 and n <= 40 and (not best or n > best) then
      best = n
    end
  end
  if best then
    return best
  end
  for digits in string.gmatch(title, "(%d+)[^%a%d]-%+") do
    local n = tonumber(digits)
    if n and n >= 1 and n <= 40 and (not best or n > best) then
      best = n
    end
  end
  return best
end

local function ResolveLevelText(title)
  if type(title) == "string" and string.match(title, "^|Kk%d+|k$") then
    return title
  end
  return nil
end

local function NormalizeRole(value)
  if type(value) ~= "string" then
    return nil
  end
  local role = string.upper(value)
  return VALID_ROLES[role] and role or nil
end

local function ReadRoleFromTable(info)
  if type(info) ~= "table" then
    return nil
  end
  for _, key in ipairs({ "role", "selectedRole", "assignedRole", "inviteRole", "desiredRole" }) do
    local role = NormalizeRole(info[key])
    if role then
      return role
    end
  end
  return nil
end

local function ResolveMapIDFromActivityIDs(activityIDs, resolveMapIDByActivityID)
  if type(activityIDs) ~= "table" or type(resolveMapIDByActivityID) ~= "function" then
    return nil
  end
  local resolvedMapID = nil
  for _, activityID in ipairs(activityIDs) do
    local numericActivityID = NormalizeID(activityID)
    if numericActivityID then
      local mapID = resolveMapIDByActivityID(numericActivityID)
      mapID = NormalizeID(mapID)
      if not mapID then
        return nil
      end
      if resolvedMapID and resolvedMapID ~= mapID then
        return nil
      end
      resolvedMapID = mapID
    end
  end
  return resolvedMapID
end

local function ResolveSearchResultMapID(info, resolveMapIDByActivityID)
  if type(info) ~= "table" then
    return nil
  end
  local mapID = ResolveMapIDFromActivityIDs(info.activityIDs, resolveMapIDByActivityID)
  if mapID then
    return mapID
  end
  local activityID = NormalizeID(info.activityID or info.primaryActivityID)
  if activityID and type(resolveMapIDByActivityID) == "function" then
    return NormalizeID(resolveMapIDByActivityID(activityID))
  end
  return nil
end

local function FirstActivityID(info)
  if type(info) ~= "table" then
    return nil
  end
  if type(info.activityIDs) == "table" then
    for _, activityID in ipairs(info.activityIDs) do
      local numeric = NormalizeID(activityID)
      if numeric then
        return numeric
      end
    end
  end
  return NormalizeID(info.activityID or info.primaryActivityID)
end

local function BuildEntryFromSearchResult(searchResultID, info, opts)
  opts = opts or {}
  if type(info) ~= "table" then
    return {
      searchResultID = searchResultID,
    }
  end
  local mapID = ResolveSearchResultMapID(info, opts.resolveMapIDByActivityID)
  local groupName = type(info.name) == "string" and info.name ~= "" and info.name or nil
  local comment = type(info.comment) == "string" and info.comment ~= "" and info.comment or nil
  local leaderName = type(info.leaderName) == "string" and info.leaderName ~= "" and info.leaderName or nil
  local titleLevel = ParseTitleKeyLevel(groupName)
  local levelText = titleLevel and nil or ResolveLevelText(groupName)
  local dungeonName = nil
  if mapID and type(opts.getDungeonName) == "function" then
    dungeonName = opts.getDungeonName(mapID)
  end
  if type(dungeonName) ~= "string" or dungeonName == "" then
    dungeonName = nil
  end

  return {
    searchResultID = searchResultID,
    mapID = mapID,
    activityID = FirstActivityID(info),
    dungeonName = dungeonName,
    level = titleLevel,
    levelText = levelText,
    groupName = groupName,
    comment = comment,
    leaderName = leaderName,
    role = ReadRoleFromTable(info),
  }
end

local function ReadSearchResultInfo(searchResultID, getSearchResultInfo)
  if type(getSearchResultInfo) ~= "function" then
    return nil
  end
  local ok, info = pcall(getSearchResultInfo, searchResultID)
  if not ok or type(info) ~= "table" then
    return nil
  end
  return info
end

local function ReadApplicationInfo(appID, getApplicationInfo)
  if type(getApplicationInfo) ~= "function" then
    return {}
  end
  local values = { pcall(getApplicationInfo, appID) }
  if not values[1] then
    return {}
  end
  return { unpack(values, 2) }
end

local function ExtractApplicationSnapshot(values, defaultID, getSearchResultInfo)
  local snapshot = {
    searchResultID = nil,
    status = nil,
    role = nil,
  }
  if type(values[1]) == "table" and #values == 1 then
    local data = values[1]
    snapshot.searchResultID = NormalizeID(data.searchResultID or data.resultID or data.listingID or data.id)
    snapshot.status = NormalizeStatus(data.applicationStatus or data.appStatus or data.status)
    snapshot.role = ReadRoleFromTable(data)
    if type(data.searchResultInfo) == "table" then
      snapshot.searchResultInfo = data.searchResultInfo
    end
    return snapshot
  end

  for _, value in ipairs(values) do
    local status = NormalizeStatus(value)
    if status and not snapshot.status then
      snapshot.status = status
    elseif type(value) == "table" then
      snapshot.role = snapshot.role or ReadRoleFromTable(value)
      if not snapshot.searchResultInfo and (value.activityID or value.activityIDs or value.name) then
        snapshot.searchResultInfo = value
      end
      snapshot.searchResultID = snapshot.searchResultID
        or NormalizeID(value.searchResultID or value.resultID or value.listingID or value.id)
    elseif type(value) == "number" and not snapshot.searchResultID then
      local candidateID = NormalizeID(value)
      if candidateID and ReadSearchResultInfo(candidateID, getSearchResultInfo) then
        snapshot.searchResultID = candidateID
      end
    end
  end

  snapshot.searchResultID = snapshot.searchResultID or NormalizeID(defaultID)
  return snapshot
end

local function SortEntries(entries)
  table.sort(entries, function(a, b)
    local left = tonumber(a.addedAt) or 0
    local right = tonumber(b.addedAt) or 0
    if left ~= right then
      return left < right
    end
    return (tonumber(a.searchResultID) or 0) < (tonumber(b.searchResultID) or 0)
  end)
end

function Invites.CreateController(opts)
  opts = opts or {}
  local entries = {}
  local subscribers = {}
  local sequence = 0

  local controller = {}

  local function Notify()
    local snapshot = controller.GetOpenInvites()
    for callback in pairs(subscribers) do
      callback(snapshot)
    end
  end

  local function UpsertInvite(searchResultID, appRole, explicitInfo)
    searchResultID = NormalizeID(searchResultID)
    if not searchResultID then
      return false
    end

    local info = explicitInfo or ReadSearchResultInfo(searchResultID, opts.getSearchResultInfo)
    local entry = BuildEntryFromSearchResult(searchResultID, info, opts)
    if not entry then
      return false
    end
    entry.role = NormalizeRole(appRole) or entry.role

    local existing = entries[searchResultID]
    if existing then
      for key, value in pairs(entry) do
        if value ~= nil then
          existing[key] = value
        end
      end
    else
      sequence = sequence + 1
      entry.addedAt = sequence
      entries[searchResultID] = entry
    end
    Notify()
    return true
  end

  local function RemoveInvite(searchResultID, notify)
    searchResultID = NormalizeID(searchResultID)
    if not searchResultID or not entries[searchResultID] then
      return false
    end
    entries[searchResultID] = nil
    if notify ~= false then
      Notify()
    end
    return true
  end

  function controller.HandleApplicationStatus(searchResultID, status)
    local normalizedStatus = NormalizeStatus(status)
    if not normalizedStatus then
      return false
    end
    if OPEN_INVITE_STATUSES[normalizedStatus] then
      return UpsertInvite(searchResultID)
    end
    if CLOSED_INVITE_STATUSES[normalizedStatus] then
      if normalizedStatus == "inviteaccepted" or normalizedStatus == "accepted" then
        controller.ClearAll()
        return true
      end
      return RemoveInvite(searchResultID)
    end
    return false
  end

  function controller.RehydrateFromBlizzard()
    if type(opts.getApplications) ~= "function" or type(opts.getApplicationInfo) ~= "function" then
      return false
    end
    local ok, applicationIDs = pcall(opts.getApplications)
    if not ok or type(applicationIDs) ~= "table" then
      return false
    end

    local changed = false
    for _, appID in ipairs(applicationIDs) do
      local values = ReadApplicationInfo(appID, opts.getApplicationInfo)
      local snapshot = ExtractApplicationSnapshot(values, appID, opts.getSearchResultInfo)
      if snapshot.status and OPEN_INVITE_STATUSES[snapshot.status] then
        changed = UpsertInvite(snapshot.searchResultID, snapshot.role, snapshot.searchResultInfo) or changed
      end
    end
    return changed
  end

  function controller.Accept(searchResultID)
    searchResultID = NormalizeID(searchResultID)
    if not searchResultID or type(opts.acceptInvite) ~= "function" then
      return false
    end
    local ok, result = pcall(opts.acceptInvite, searchResultID)
    if not ok or result == false then
      return false
    end
    controller.ClearAll()
    return true
  end

  function controller.Decline(searchResultID)
    searchResultID = NormalizeID(searchResultID)
    if not searchResultID or type(opts.declineInvite) ~= "function" then
      return false
    end
    local ok, result = pcall(opts.declineInvite, searchResultID)
    if not ok or result == false then
      return false
    end
    RemoveInvite(searchResultID)
    return true
  end

  function controller.ClearAll()
    local hadEntries = next(entries) ~= nil
    entries = {}
    if hadEntries then
      Notify()
    end
    return hadEntries
  end

  function controller.GetOpenInvites()
    local list = {}
    for _, entry in pairs(entries) do
      list[#list + 1] = CopyEntry(entry)
    end
    SortEntries(list)
    return list
  end

  function controller.Subscribe(callback)
    if type(callback) ~= "function" then
      return function() end
    end
    subscribers[callback] = true
    callback(controller.GetOpenInvites())
    return function()
      subscribers[callback] = nil
    end
  end

  return controller
end

Invites._Internal = {
  ParseTitleKeyLevel = ParseTitleKeyLevel,
  ExtractApplicationSnapshot = ExtractApplicationSnapshot,
  NormalizeRole = NormalizeRole,
}
