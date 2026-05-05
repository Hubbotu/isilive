local _, addonTable = ...

addonTable = addonTable or {}

-- Always-on error capture for isiLive's own code. Hooks into WoW's global
-- error handler chain (geterrorhandler / seterrorhandler) and persists a
-- bounded ring of error entries into IsiLiveDB.errorLog. Survives /reload
-- and account-wide login. Visible in-game via /isilive errorlog.
--
-- Design constraints:
--   1. Always-on, no opt-in. Errors are rare and valuable; we want them
--      captured even from users who never enable runtimeLog.
--   2. Chain-of-responsibility: the previous error handler (often
--      BugSack / !BugGrabber / Blizzard's BasicScriptErrors) is ALWAYS
--      called. We are an additional subscriber, never a replacement.
--   3. Filter to isiLive code: only capture errors whose stack trace
--      mentions "isiLive". Bypassing this would flood the buffer with
--      Plater / WeakAuras / Blizzard UI errors that aren't ours to fix.
--   4. Dedup: identical errors fire repeatedly during a single combat
--      tick. Increment a counter on the existing entry instead of
--      appending 200 duplicates.
--   5. Bounded ring: hard cap at MAX_ENTRIES, no unbounded growth.
--   6. Defensive: every internal step is pcall-wrapped. An error in the
--      error logger itself must NOT cause a secondary cascade.
local ErrorLog = {}
addonTable.ErrorLog = ErrorLog

local MAX_ENTRIES = 100
local FILTER_TOKEN = "isiLive"

local installedHandler = nil
local installed = false

local function GetDB()
  return rawget(_G, "IsiLiveDB")
end

local function EnsureStorage()
  local db = GetDB()
  if type(db) ~= "table" then
    return nil
  end
  if type(db.errorLog) ~= "table" then
    db.errorLog = {}
  end
  return db.errorLog
end

local function NowTimestamp()
  local getTime = rawget(_G, "GetTime")
  if type(getTime) == "function" then
    local ok, value = pcall(getTime)
    if ok and type(value) == "number" then
      return value
    end
  end
  local dateFn = rawget(_G, "date")
  if type(dateFn) == "function" then
    local ok, value = pcall(dateFn, "%H:%M:%S")
    if ok and type(value) == "string" then
      return value
    end
  end
  return 0
end

local function NowDisplayTimestamp()
  local dateFn = rawget(_G, "date")
  if type(dateFn) == "function" then
    local ok, value = pcall(dateFn, "%Y-%m-%d %H:%M:%S")
    if ok and type(value) == "string" then
      return value
    end
  end
  return tostring(NowTimestamp())
end

-- Detects whether a given error message text mentions isiLive. The match is
-- intentionally permissive (any case) so manually-thrown errors with
-- "isiLive: ..." prefixes also surface.
local function MentionsIsiLive(text)
  if type(text) ~= "string" or text == "" then
    return false
  end
  if text:find(FILTER_TOKEN, 1, true) then
    return true
  end
  if text:lower():find(FILTER_TOKEN:lower(), 1, true) then
    return true
  end
  return false
end

-- Enriches the raw error message with a stack traceback. Scoped via pcall
-- so a broken debug library cannot itself trigger an error during error
-- handling.
local function CaptureStack(message)
  local debugLib = rawget(_G, "debug")
  if type(debugLib) ~= "table" or type(debugLib.traceback) ~= "function" then
    return tostring(message)
  end
  local ok, value = pcall(debugLib.traceback, tostring(message), 2)
  if ok and type(value) == "string" then
    return value
  end
  return tostring(message)
end

-- Looks up an existing entry with the same fullText. Returns the entry and
-- its index, or nil for both. fullText already includes traceback if present.
local function FindExistingEntry(storage, fullText)
  if type(storage) ~= "table" or type(fullText) ~= "string" then
    return nil, nil
  end
  for index, entry in ipairs(storage) do
    if type(entry) == "table" and entry.fullText == fullText then
      return entry, index
    end
  end
  return nil, nil
end

-- Trims the storage to MAX_ENTRIES by dropping the oldest entries (entries
-- with the lowest lastSeen timestamps). Idempotent.
local function TrimToCap(storage)
  if type(storage) ~= "table" then
    return
  end
  while #storage > MAX_ENTRIES do
    -- Find oldest by lastSeen and drop it.
    local oldestIndex = 1
    local oldestSeen = nil
    for i, entry in ipairs(storage) do
      local seen = type(entry) == "table" and tonumber(entry.lastSeen) or 0
      if oldestSeen == nil or seen < oldestSeen then
        oldestSeen = seen
        oldestIndex = i
      end
    end
    table.remove(storage, oldestIndex)
  end
end

--- Captures an error into the ring buffer. Public so manually-detected
--- internal errors (e.g. validator violations) can also feed in.
-- @param message string Raw error message.
-- @param stack string|nil Optional traceback (auto-generated if absent).
-- @param source string|nil Optional source label (e.g. "controller_wiring").
function ErrorLog.Capture(message, stack, source)
  local ok, err = pcall(function()
    local storage = EnsureStorage()
    if not storage then
      return
    end

    local fullText = type(stack) == "string" and stack or CaptureStack(message)
    if not MentionsIsiLive(fullText) and not MentionsIsiLive(message) then
      return
    end

    local existing = FindExistingEntry(storage, fullText)
    local now = NowTimestamp()
    if existing then
      existing.count = (tonumber(existing.count) or 1) + 1
      existing.lastSeen = now
      existing.lastSeenDisplay = NowDisplayTimestamp()
      return
    end

    local entry = {
      message = tostring(message or ""),
      fullText = fullText,
      source = type(source) == "string" and source or nil,
      count = 1,
      firstSeen = now,
      lastSeen = now,
      firstSeenDisplay = NowDisplayTimestamp(),
      lastSeenDisplay = NowDisplayTimestamp(),
    }
    storage[#storage + 1] = entry
    TrimToCap(storage)
  end)
  -- If the error logger itself errors, fall through silently; the original
  -- error has already been forwarded to the upstream handler by Install().
  if not ok then
    local chatFrame = rawget(_G, "DEFAULT_CHAT_FRAME")
    if type(chatFrame) == "table" and type(chatFrame.AddMessage) == "function" then
      -- Last-resort visibility for development builds. In live, swallowed.
      pcall(chatFrame.AddMessage, chatFrame, "|cffff4040[isiLive ErrorLog]|r capture failure: " .. tostring(err))
    end
  end
end

--- Installs the error-handler hook. Idempotent — calling twice has no effect.
-- Chains to whatever handler was previously installed (Blizzard default,
-- BugSack, etc.) so we never silence other addons' error UIs.
function ErrorLog.Install()
  if installed then
    return
  end

  local getEH = rawget(_G, "geterrorhandler")
  local setEH = rawget(_G, "seterrorhandler")
  if type(getEH) ~= "function" or type(setEH) ~= "function" then
    return
  end

  local previous = getEH()
  installedHandler = function(message)
    -- Always forward to the previous handler FIRST so other listeners
    -- (BugSack, BasicScriptErrors) receive the error even if our capture
    -- raises secondarily.
    if type(previous) == "function" then
      pcall(previous, message)
    end
    ErrorLog.Capture(message, nil, nil)
  end
  setEH(installedHandler)
  installed = true
end

--- Returns the most recent N entries (oldest-first within the returned slice).
-- @param limit number|nil Default 10, max 100.
-- @return table list of entry tables
function ErrorLog.GetTail(limit)
  local storage = EnsureStorage()
  if not storage then
    return {}
  end
  local clampedLimit = tonumber(limit) or 10
  if clampedLimit < 1 then
    clampedLimit = 1
  elseif clampedLimit > MAX_ENTRIES then
    clampedLimit = MAX_ENTRIES
  end
  local total = #storage
  if total == 0 then
    return {}
  end
  local startIndex = math.max(1, total - clampedLimit + 1)
  local result = {}
  for i = startIndex, total do
    result[#result + 1] = storage[i]
  end
  return result
end

--- Returns the total number of distinct entries currently stored.
function ErrorLog.GetCount()
  local storage = EnsureStorage()
  return type(storage) == "table" and #storage or 0
end

--- Clears all stored error entries. Reversible only via re-occurrence.
function ErrorLog.Clear()
  local storage = EnsureStorage()
  if storage then
    for i = #storage, 1, -1 do
      storage[i] = nil
    end
  end
end

--- Returns the hard cap on entries (for tests and slash-command UX).
function ErrorLog.GetMaxEntries()
  return MAX_ENTRIES
end

--- Reports whether Install() ran successfully.
function ErrorLog.IsInstalled()
  return installed
end

return ErrorLog
