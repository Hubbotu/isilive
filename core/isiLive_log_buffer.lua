local _, addonTable = ...

addonTable = addonTable or {}

local LogBuffer = {}
addonTable.LogBuffer = LogBuffer

local function ClampLimit(limit, defaultValue, minValue, maxValue)
  local value = tonumber(limit) or defaultValue
  if value < minValue then
    value = minValue
  elseif value > maxValue then
    value = maxValue
  end
  return math.floor(value)
end

local function RingIndex(head, offset, cap)
  return ((head - 1 + offset) % cap) + 1
end

local function NormalizeRing(logs, cap)
  local count = tonumber(logs._count)
  local head = tonumber(logs._head)
  if count and head and count >= 0 and head >= 1 and head <= cap then
    if count > cap then
      count = cap
      logs._count = count
    end
    return count, head
  end

  local total = #logs
  local keep = total
  if keep > cap then
    keep = cap
  end
  local startIndex = total - keep + 1
  if startIndex < 1 then
    startIndex = 1
  end

  for i = 1, keep do
    logs[i] = logs[startIndex + i - 1]
  end
  for i = keep + 1, total do
    logs[i] = nil
  end

  logs._count = keep
  logs._head = 1
  return keep, 1
end

function LogBuffer.EnsureSavedTable(key)
  assert(type(key) == "string" and key ~= "", "isiLive: LogBuffer requires non-empty key")

  return function()
    local db = rawget(_G, "IsiLiveDB")
    if not db then
      db = {}
      IsiLiveDB = db
    end
    if type(db[key]) ~= "table" then
      db[key] = {}
    end
    return db[key]
  end
end

function LogBuffer.SanitizeMessage(message)
  local text = tostring(message or "")
  -- Keep SavedVariables debug logs ASCII-friendly for easier external parsing.
  return text:gsub("[\128-\255]", "")
end

function LogBuffer.Append(logs, timestamp, message, maxEntries)
  assert(type(logs) == "table", "isiLive: LogBuffer.Append requires logs table")
  local cap = tonumber(maxEntries) or #logs
  if cap < 1 then
    cap = 1
  end

  local count, head = NormalizeRing(logs, cap)
  local timestampText = tostring(timestamp or "")
  local messageText = LogBuffer.SanitizeMessage(message)
  local entry = timestampText ~= "" and string.format("%s %s", timestampText, messageText) or messageText
  if count < cap then
    logs[RingIndex(head, count, cap)] = entry
    logs._count = count + 1
    logs._head = head
    return
  end

  logs[head] = entry
  logs._count = cap
  logs._head = RingIndex(head, 1, cap)
end

function LogBuffer.Count(logs)
  assert(type(logs) == "table", "isiLive: LogBuffer.Count requires logs table")
  return tonumber(logs._count) or #logs
end

function LogBuffer.GetTail(logs, limit, defaultLimit, maxLimit)
  assert(type(logs) == "table", "isiLive: LogBuffer.GetTail requires logs table")

  local count = ClampLimit(limit, tonumber(defaultLimit) or 20, 1, tonumber(maxLimit) or 100)
  local total = LogBuffer.Count(logs)
  local startIndex = total - count + 1
  if startIndex < 1 then
    startIndex = 1
  end

  local out = {}
  local cap = #logs
  if cap < 1 then
    return out
  end

  local head = tonumber(logs._head) or 1
  for offset = startIndex - 1, total - 1 do
    out[#out + 1] = logs[RingIndex(head, offset, cap)]
  end
  return out
end
