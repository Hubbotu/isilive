local _, addonTable = ...

addonTable = addonTable or {}

local StringUtils = {}
addonTable.StringUtils = StringUtils

--- Trims leading and trailing whitespace from a string.
--- @param value string|nil
--- @return string
function StringUtils.Trim(value)
  if type(value) ~= "string" then
    return ""
  end
  return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Removes all whitespace from a string.
--- @param value string|nil
--- @return string
function StringUtils.StripWhitespace(value)
  if type(value) ~= "string" then
    return ""
  end
  return (value:gsub("%s+", ""))
end

--- Normalizes a realm name by stripping spaces, dashes, dots, parens, and quotes.
--- Canonical pattern shared by Sync.NormalizePlayerKey, Stats.NormalizeName,
--- and Locale.NormalizeRealmLookupKey.
--- @param realm string|nil
--- @return string
function StringUtils.NormalizeRealmName(realm)
  if type(realm) ~= "string" then
    return ""
  end
  return (realm:gsub("[%s%-%.%(%)'`]", ""))
end

--- Returns true when value is nil, not a string, or the empty string.
--- Equivalent to `not value or value == ""` for string-typed inputs.
--- @param value any
--- @return boolean
function StringUtils.IsBlank(value)
  return type(value) ~= "string" or value == ""
end

--- Builds a `name-realm` cross-realm qualified target string used by /target,
--- /whisper, and other slash commands that accept a character name. Returns
--- the bare name when realm is blank, and nil when name itself is blank.
--- @param name string|nil
--- @param realm string|nil
--- @return string|nil
function StringUtils.BuildQualifiedName(name, realm)
  if type(name) ~= "string" or name == "" then
    return nil
  end
  if type(realm) == "string" and realm ~= "" then
    return name .. "-" .. realm
  end
  return name
end
