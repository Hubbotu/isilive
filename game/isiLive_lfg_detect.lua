local _, addonTable = ...

addonTable = addonTable or {}

-- ---------------------------------------------------------------------------
-- LFG Dungeon Detection
-- Detects which dungeon the player received an invite for, or which dungeon
-- they queued for via their own active LFG listing.
-- Outputs a chat message with the detected dungeon name.
-- ---------------------------------------------------------------------------

local LFGDetect = {}
addonTable.LFGDetect = LFGDetect
local Unpack = rawget(_G, "unpack") or rawget(table, "unpack")

-- Static map: LFG activity ID -> challenge map ID for all active-season dungeons.
-- Primary fast path: zero-latency, no API call, taint-safe.
-- The LFG API (C_LFGList.GetActivityInfoTable) can return tainted/secret values
-- during raid state or when the API cache is cold (first event after login).
-- The static map guarantees a correct answer even in those edge cases.
-- New season: add entries here AND in SeasonData.mapToTeleport — both must stay in sync.
local ACTIVITY_TO_MAP = {
  [1542] = 557, -- Windrunner Spire
  [182] = 161, -- Skyreach
  [486] = 239, -- Seat of the Triumvirate
  [1770] = 556, -- Pit of Saron
  [1768] = 559, -- Nexus-Point Xenas
  [1764] = 560, -- Maisara Caverns
  [1760] = 558, -- Magisters' Terrace
  [1160] = 402, -- Algeth'ar Academy
}

-- Resolve mapID from a single activityID.
-- Resolution order:
--   1. ACTIVITY_TO_MAP  — static, zero-latency, taint-safe (primary)
--   2. C_LFGList.GetActivityInfoTable — dynamic fallback for IDs not in the static map;
--      result is cached into ACTIVITY_TO_MAP so subsequent calls are free.
local function MapIDFromActivityID(activityID)
  if not activityID then
    return nil
  end
  local numID = tonumber(activityID)
  if not numID or numID <= 0 then
    return nil
  end

  -- 1. Static map: fast, taint-safe, reliable even when the API cache is cold
  if ACTIVITY_TO_MAP[numID] then
    return ACTIVITY_TO_MAP[numID]
  end

  -- 2. Dynamic fallback via WoW API (may be tainted/cold; protected by pcall)
  local lfgList = rawget(_G, "C_LFGList")
  if type(lfgList) == "table" and type(lfgList.GetActivityInfoTable) == "function" then
    local ok, info = pcall(lfgList.GetActivityInfoTable, numID)
    if ok and type(info) == "table" then
      local mapID = tonumber(rawget(info, "mapID") or rawget(info, "mapId"))
      if mapID and mapID > 0 then
        ACTIVITY_TO_MAP[numID] = mapID -- cache for future calls
        return mapID
      end
    end
  end

  return nil
end

-- Resolve mapID from a table of activityIDs.
local function MapIDFromActivityIDs(activityIDs)
  if type(activityIDs) ~= "table" then
    return nil
  end

  local resolvedMapID = nil
  for _, actID in pairs(activityIDs) do
    local numericActivityID = tonumber(actID)
    if numericActivityID and numericActivityID > 0 then
      local mapID = MapIDFromActivityID(numericActivityID)
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

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

-- [searchResultID] = { mapID, leaderName }  — pending invites not yet accepted.
-- leaderName is the LFG group leader as returned by C_LFGList.GetSearchResultInfo;
-- used later as a tie-breaker when multiple roster members hold a key for the same
-- dungeon (the leader is in practice the key owner).
local pendingInvites = {}
-- mapID of the last detected own queue listing (nil = no active listing)
local lastQueueMapID = nil
-- mapID currently highlighted (invite or accepted invite, or own queue) — nil = none
local detectedMapID = nil
-- mapID from a just-accepted invite that is waiting for the roster to settle.
-- This prevents a transient non-group roster update from clearing a valid highlight.
local pendingAcceptedInviteMapID = nil
-- Leader name of the LFG group whose invite produced the current detectedMapID
-- (nil = detectedMapID was not set via invite path, or roster is post-reset).
-- Consumers use this to disambiguate ResolveActiveKeyOwnerUnit when the roster
-- contains multiple members with the same keyMapID.
local activeInviteLeader = nil
-- Hint key level parsed from the LFG group title (e.g. "+13 Competitive" → 13).
-- Used as a last-resort fallback for the "Ziel-Dungeon: X +N" announce when
-- neither a roster owner nor a synced target supplies a level (typical for
-- groups whose leader does not run isiLive). nil = no hint available.
local activeInviteTitleLevel = nil

-- Injected by the factory after UpdateMPlusTeleportButton is available.
-- Replaces the previous direct _factoryCtx access (ARCH-1 fix).
local highlightCallback = nil
local groupRosterTraceLogger = nil

local debugLog = nil
local debugTrace = nil
local debugTraceDeep = nil
local lastRosterUpdateSignature = nil
local TriggerHighlightUpdate

local function GetGroupMemberCount()
  local getNumGroupMembers = rawget(_G, "GetNumGroupMembers")
  if type(getNumGroupMembers) ~= "function" then
    return nil
  end

  local ok, count = pcall(getNumGroupMembers)
  if not ok then
    return nil
  end

  count = tonumber(count)
  if not count then
    return nil
  end

  return math.max(0, math.floor(count))
end

-- Called once from InitializeFactoryPrimaryControllers to wire the callbacks.
function LFGDetect.SetHighlightCallback(fn)
  highlightCallback = type(fn) == "function" and fn or nil
  if highlightCallback and detectedMapID then
    -- If the callback is wired after the LFG state was already resolved,
    -- replay the current state once so the UI cannot miss the highlight.
    TriggerHighlightUpdate("queue")
  end
end

function LFGDetect.SetGroupRosterTraceLogger(fn)
  groupRosterTraceLogger = type(fn) == "function" and fn or nil
end

function LFGDetect.SetLogger(fn)
  debugLog = type(fn) == "function" and fn or nil
end

function LFGDetect.SetTraceLogger(fn)
  debugTrace = type(fn) == "function" and fn or nil
end

function LFGDetect.SetDeepTraceLogger(fn)
  debugTraceDeep = type(fn) == "function" and fn or nil
end

local function LogInternal(traceFn, event, formatText, ...)
  if not traceFn and not debugLog then
    return
  end
  local argCount = select("#", ...)
  if traceFn then
    local args = { ... }
    traceFn(function()
      local data = formatText
      if argCount > 0 then
        data = string.format(tostring(formatText or ""), Unpack(args))
      end
      return string.format("[LFG] %s %s", event, data or "")
    end)
    return
  end
  local data = formatText
  if argCount > 0 then
    data = string.format(tostring(formatText or ""), ...)
  end
  if debugLog then
    debugLog(string.format("[LFG] %s %s", event, data or ""))
  end
end

local function Log(event, formatText, ...)
  LogInternal(debugTrace, event, formatText, ...)
end

local function LogDeep(event, formatText, ...)
  LogInternal(debugTraceDeep, event, formatText, ...)
end

local function EmitGroupRosterTrace(inGroup, groupMemberCount, detectedBefore)
  if type(groupRosterTraceLogger) ~= "function" then
    return
  end

  groupRosterTraceLogger({
    event = "GROUP_ROSTER_UPDATE",
    inGroup = inGroup == true,
    members = groupMemberCount,
    detectedBefore = detectedBefore,
    detectedAfter = detectedMapID,
    pendingAccept = pendingAcceptedInviteMapID,
    latestQueueMap = lastQueueMapID,
  })
end

-- ---------------------------------------------------------------------------
-- Invite detection
-- ---------------------------------------------------------------------------

-- Best-effort parser that pulls a key-level hint out of an LFG group title.
-- LFG leaders by convention encode the level as "+N", "+N something", "(+N)",
-- "N+" etc. We pick the highest plausible match (1..40) so descriptive prefixes
-- like "+12 / +13 swap" still resolve to the actual played level. nil = no hint.
local function ParseTitleKeyLevel(title)
  if type(title) ~= "string" or title == "" then
    return nil
  end
  local best = nil
  -- Pattern A: "+N" with optional whitespace separator. Captures the digits.
  for digits in string.gmatch(title, "%+%s*(%d+)") do
    local n = tonumber(digits)
    if n and n >= 1 and n <= 40 then
      if not best or n > best then
        best = n
      end
    end
  end
  if best then
    return best
  end
  -- Pattern B: "N+" trailing-plus form (less common but still seen).
  for digits in string.gmatch(title, "(%d+)%s*%+") do
    local n = tonumber(digits)
    if n and n >= 1 and n <= 40 then
      if not best or n > best then
        best = n
      end
    end
  end
  return best
end

local function OnInvited(searchResultID)
  local C_LFGList_ref = rawget(_G, "C_LFGList")
  if type(C_LFGList_ref) ~= "table" then
    return
  end

  local info = nil
  if type(searchResultID) == "number" and searchResultID > 0 then
    local ok, result = pcall(C_LFGList_ref.GetSearchResultInfo, searchResultID)
    if ok then
      info = result
    end
  end

  local mapID = nil

  local hasActivityIDs = type(info) == "table" and type(info.activityIDs) == "table" and next(info.activityIDs) ~= nil

  -- Try activityIDs table first (most reliable)
  if hasActivityIDs then
    mapID = MapIDFromActivityIDs(info.activityIDs)
  end

  -- Try single activityID
  if not mapID and not hasActivityIDs and type(info) == "table" and info.activityID then
    mapID = MapIDFromActivityID(info.activityID)
  end

  Log(
    "invite_received",
    "searchResultID=%s activityID=%s mapID=%s",
    tostring(searchResultID),
    tostring(info and info.activityID),
    tostring(mapID)
  )
  if mapID then
    local leaderName = nil
    if type(info) == "table" and type(info.leaderName) == "string" and info.leaderName ~= "" then
      leaderName = info.leaderName
    end
    local titleLevel = nil
    if type(info) == "table" then
      titleLevel = ParseTitleKeyLevel(info.name)
    end
    pendingInvites[searchResultID] = { mapID = mapID, leaderName = leaderName, titleLevel = titleLevel }
    Log(
      "state_set",
      "var=pendingInvites[%s] mapID=%s leader=%s titleLevel=%s",
      tostring(searchResultID),
      tostring(mapID),
      tostring(leaderName),
      tostring(titleLevel)
    )
  end
end

-- BUG-1 fix: soundContext propagated so own-queue and invite updates suppress the portal sound.
-- ARCH-1 fix: uses the injected highlightCallback instead of reaching into _factoryCtx.
TriggerHighlightUpdate = function(soundContext)
  Log("highlight_trigger", "soundContext=%s detectedMapID=%s", tostring(soundContext), tostring(detectedMapID))
  if type(highlightCallback) == "function" then
    highlightCallback(soundContext)
  end
end

local function OnInviteAccepted(searchResultID)
  local entry = pendingInvites[searchResultID]
  local mapID = type(entry) == "table" and entry.mapID or nil
  local leaderName = type(entry) == "table" and entry.leaderName or nil
  local titleLevel = type(entry) == "table" and entry.titleLevel or nil
  Log(
    "invite_accepted",
    "searchResultID=%s mapID=%s leader=%s titleLevel=%s",
    tostring(searchResultID),
    tostring(mapID),
    tostring(leaderName),
    tostring(titleLevel)
  )
  if mapID then
    pendingInvites[searchResultID] = nil
    activeInviteLeader = leaderName
    activeInviteTitleLevel = titleLevel
    pendingAcceptedInviteMapID = mapID
    if detectedMapID ~= mapID then
      Log("state_set", "var=detectedMapID before=%s after=%s", tostring(detectedMapID), tostring(mapID))
      detectedMapID = mapID
      Log("state_set", "var=pendingAcceptedInviteMapID val=%s", tostring(mapID))
    end
    Log("state_set", "var=activeInviteLeader val=%s", tostring(leaderName))
    Log("state_set", "var=activeInviteTitleLevel val=%s", tostring(titleLevel))
    TriggerHighlightUpdate("invite")
  end
end

local function OnInviteDeclined(searchResultID)
  local entry = pendingInvites[searchResultID]
  local mapID = type(entry) == "table" and entry.mapID or nil
  Log("invite_declined", "searchResultID=%s mapID=%s", tostring(searchResultID), tostring(mapID))
  pendingInvites[searchResultID] = nil
  if mapID and detectedMapID == mapID then
    detectedMapID = nil
    activeInviteLeader = nil
    activeInviteTitleLevel = nil
    TriggerHighlightUpdate("queue")
  end
end

local NEGATIVE_STATUSES = {
  declined = true,
  declined_full = true,
  declined_delisted = true,
  cancelled = true,
  failed = true,
  timedout = true,
  invitedeclined = true,
}

local function HandleApplicationStatus(searchResultID, newStatus)
  -- BUG-3 fix: normalize to lowercase so casing variations from the Blizzard API
  -- ("Invited", "InviteAccepted", …) are handled the same as the lowercase form.
  local normalizedStatus = type(newStatus) == "string" and string.lower(newStatus) or ""
  if normalizedStatus == "invited" then
    OnInvited(searchResultID)
  elseif normalizedStatus == "inviteaccepted" then
    OnInviteAccepted(searchResultID)
  elseif NEGATIVE_STATUSES[normalizedStatus] then
    OnInviteDeclined(searchResultID)
  end
end

-- ---------------------------------------------------------------------------
-- Own queue detection (active listing + 5s poll)
-- ---------------------------------------------------------------------------

-- BUG-2 fix: pendingInvites is NOT cleared here. The 5s ticker calls CheckActiveGroup
-- which calls ClearDetectedState when no active listing exists. If a player received
-- an invite (no own listing) and the ticker fires before they accept, pendingInvites
-- must survive so OnInviteAccepted can still resolve the mapID.
-- pendingInvites is only cleared in ClearAllState (group-leave or explicit factory reset).
--
-- BUG-LFG-4 fix: only clear state that the queue-listing path owns.
-- lastQueueMapID is set exclusively by CheckActiveGroup when an active listing is
-- found. Invite-set detectedMapID (lastQueueMapID == nil) must survive the 5s ticker
-- so the portal highlight stays active until the player enters the dungeon or leaves
-- the group (both handled by ClearAllStateImpl).
local function ClearDetectedState()
  if lastQueueMapID ~= nil then
    Log("clear_detected_state", "path=queue_ticker lastQueueMapID=%s", tostring(lastQueueMapID))
    detectedMapID = nil
    lastQueueMapID = nil
    activeInviteLeader = nil
    activeInviteTitleLevel = nil
    TriggerHighlightUpdate("queue")
  end
end

-- Full reset: called on group-leave and explicit factory reset where pending invite
-- state is no longer relevant.
local function ClearAllStateImpl()
  local hadState = detectedMapID ~= nil
    or lastQueueMapID ~= nil
    or next(pendingInvites) ~= nil
    or pendingAcceptedInviteMapID ~= nil
    or activeInviteLeader ~= nil
    or activeInviteTitleLevel ~= nil
  Log("clear_all_state", "hadState=%s", tostring(hadState))
  detectedMapID = nil
  lastQueueMapID = nil
  pendingAcceptedInviteMapID = nil
  activeInviteLeader = nil
  activeInviteTitleLevel = nil
  pendingInvites = {}
  if hadState then
    TriggerHighlightUpdate("queue")
  end
end

function LFGDetect.GetDetectedMapID()
  return detectedMapID
end

function LFGDetect.GetActiveInviteLeader()
  return activeInviteLeader
end

-- Hint level parsed from the leader's free-form LFG group title
-- (e.g. "+13 Competitive" → 13). Used as a last-resort fallback for the
-- "Ziel-Dungeon: X +N" announce when no roster owner / synced target supplies
-- a level. nil = no hint available (no invite-accepted state, or no "+N"
-- pattern in the title).
function LFGDetect.GetActiveInviteTitleLevel()
  return activeInviteTitleLevel
end

function LFGDetect.ClearAllState()
  ClearAllStateImpl()
end

local function CheckActiveGroup()
  local C_LFGList_ref = rawget(_G, "C_LFGList")
  if type(C_LFGList_ref) ~= "table" or type(C_LFGList_ref.GetActiveEntryInfo) ~= "function" then
    return
  end

  local ok, info = pcall(C_LFGList_ref.GetActiveEntryInfo)
  if not ok or not info then
    -- No active listing:
    -- - while grouped, keep the current detected state so the highlight can
    --   survive roster settling until the player actually enters the dungeon
    --   or leaves the group.
    -- - while not grouped, only clear queue-owned state.
    -- - while an invite was just accepted, protect the state until
    --   GROUP_ROSTER_UPDATE fires. IsInGroup() can still return false in the
    --   window between LFG_LIST_APPLICATION_STATUS_UPDATED=inviteaccepted and
    --   the delayed GROUP_ROSTER_UPDATE; clearing here races the highlight off.
    local isInGroup = rawget(_G, "IsInGroup")
    local isInRaid = rawget(_G, "IsInRaid")
    local inGroup = (type(isInGroup) == "function" and isInGroup()) or (type(isInRaid) == "function" and isInRaid())
    if not inGroup and pendingAcceptedInviteMapID == nil then
      ClearDetectedState()
    end
    return
  end

  local mapID = nil

  local hasActivityIDs = type(info.activityIDs) == "table" and next(info.activityIDs) ~= nil
  if hasActivityIDs then
    mapID = MapIDFromActivityIDs(info.activityIDs)
  end
  if not mapID and not hasActivityIDs and info.activityID then
    mapID = MapIDFromActivityID(info.activityID)
  end

  if mapID and mapID ~= lastQueueMapID then
    Log("queue_listing_detected", "mapID=%s lastQueueMapID=%s", tostring(mapID), tostring(lastQueueMapID))
    lastQueueMapID = mapID
    detectedMapID = mapID
    Log("state_set", "var=lastQueueMapID val=%s", tostring(mapID))
    Log("state_set", "var=detectedMapID val=%s", tostring(mapID))
    TriggerHighlightUpdate("queue") -- BUG-1: own listing → suppress portal sound
  elseif not mapID and lastQueueMapID ~= nil then
    Log("queue_listing_cleared", "no_active_entry")
    lastQueueMapID = nil
    detectedMapID = nil
    TriggerHighlightUpdate("queue")
  end
end

function LFGDetect.HandleEvent(event, ...)
  if event == "PLAYER_LOGIN" then
    CheckActiveGroup()
  elseif event == "LFG_LIST_APPLICATION_STATUS_UPDATED" then
    local searchResultID, newStatus = ...
    HandleApplicationStatus(searchResultID, newStatus)
  elseif event == "LFG_LIST_ACTIVE_ENTRY_UPDATE" then
    CheckActiveGroup()
  elseif event == "GROUP_ROSTER_UPDATE" then
    local detectedBefore = detectedMapID
    local isInGroup = rawget(_G, "IsInGroup")
    local isInRaid = rawget(_G, "IsInRaid")
    local inGroup = (type(isInGroup) == "function" and isInGroup()) or (type(isInRaid) == "function" and isInRaid())
    local memberCount = GetGroupMemberCount()
    local rosterSignature =
      string.format("%s|%s|%s", tostring(inGroup), tostring(memberCount), tostring(pendingAcceptedInviteMapID))
    local rosterLogFn = rosterSignature == lastRosterUpdateSignature and LogDeep or Log
    lastRosterUpdateSignature = rosterSignature
    rosterLogFn(
      "group_roster_update",
      "inGroup=%s memberCount=%s pendingAccept=%s",
      tostring(inGroup),
      tostring(memberCount),
      tostring(pendingAcceptedInviteMapID)
    )
    if not inGroup then
      local groupMemberCount = GetGroupMemberCount()
      if groupMemberCount and groupMemberCount > 0 then
        pendingAcceptedInviteMapID = nil
        EmitGroupRosterTrace(false, groupMemberCount, detectedBefore)
        return
      end
      if groupMemberCount == 0 then
        if pendingAcceptedInviteMapID then
          EmitGroupRosterTrace(false, groupMemberCount, detectedBefore)
          return
        end
        -- Left all groups — full reset including pending invites.
        ClearAllStateImpl()
        EmitGroupRosterTrace(false, groupMemberCount, detectedBefore)
        return
      end
      ClearAllStateImpl()
      EmitGroupRosterTrace(false, groupMemberCount, detectedBefore)
      return
    end
    local groupMemberCount = GetGroupMemberCount()
    pendingAcceptedInviteMapID = nil
    -- Joined a group: if we have a pending invite but detectedMapID was not set
    -- yet (e.g. inviteaccepted fired before GROUP_ROSTER_UPDATE settled),
    -- apply it now.
    if not detectedMapID then
      local resultID, entry = next(pendingInvites)
      if resultID and type(entry) == "table" and entry.mapID then
        detectedMapID = entry.mapID
        activeInviteLeader = entry.leaderName
        activeInviteTitleLevel = entry.titleLevel
        pendingInvites[resultID] = nil
        TriggerHighlightUpdate("invite")
      else
        CheckActiveGroup()
      end
    end
    EmitGroupRosterTrace(true, groupMemberCount, detectedBefore)
  end
end
