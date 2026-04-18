#!/usr/bin/env lua
-- Scans locale/isiLive_texts.lua for drift between enUS (reference) and the
-- other locales (deDE/frFR/esES/ptBR/itIT/ruRU/trTR):
--   * missing keys in a locale (key exists in enUS but not in target)
--   * extra keys in a locale (key exists in target but not in enUS)
--   * %s/%d placeholder count mismatches (would crash string.format at runtime)
--
-- Exits 0 on clean, 1 on drift. Intended for local runs and CI.
-- Run from repo root:
--   lua tools/check_locale_drift.lua

local TEXTS_PATH = "locale/isiLive_texts.lua"

local loader = loadfile(TEXTS_PATH)
if not loader then
  io.stderr:write("drift: cannot load " .. TEXTS_PATH .. "\n")
  os.exit(2)
end

local addonTable = {}
local ok, err = pcall(loader, "isiLive", addonTable)
if not ok then
  io.stderr:write("drift: load error: " .. tostring(err) .. "\n")
  os.exit(2)
end

if not addonTable.Texts or type(addonTable.Texts.GetLocaleTables) ~= "function" then
  io.stderr:write("drift: addonTable.Texts.GetLocaleTables not available\n")
  os.exit(2)
end

local locales = addonTable.Texts.GetLocaleTables()
local ref = locales.enUS
if type(ref) ~= "table" then
  io.stderr:write("drift: enUS locale missing\n")
  os.exit(2)
end

local function countPlaceholders(s)
  local count = 0
  for _ in s:gmatch("%%[sd]") do
    count = count + 1
  end
  return count
end

local function sortedKeys(tbl)
  local keys = {}
  for k in pairs(tbl) do
    keys[#keys + 1] = k
  end
  table.sort(keys)
  return keys
end

local issues = {}

local orderedLocales = { "deDE", "frFR", "esES", "ptBR", "itIT", "ruRU", "trTR" }

for _, localeName in ipairs(orderedLocales) do
  local localeTable = locales[localeName]
  if type(localeTable) ~= "table" then
    issues[#issues + 1] = string.format("%s: locale table missing entirely", localeName)
  else
    for _, key in ipairs(sortedKeys(ref)) do
      local refValue = ref[key]
      local trValue = localeTable[key]
      if trValue == nil then
        issues[#issues + 1] = string.format("%s.%s: MISSING (enUS has this key)", localeName, key)
      elseif type(refValue) == "string" and type(trValue) == "string" then
        local refC = countPlaceholders(refValue)
        local trC = countPlaceholders(trValue)
        if refC ~= trC then
          issues[#issues + 1] = string.format(
            '%s.%s: PLACEHOLDER MISMATCH (enUS=%d, %s=%d)\n    enUS: "%s"\n    %s: "%s"',
            localeName,
            key,
            refC,
            localeName,
            trC,
            refValue,
            localeName,
            trValue
          )
        end
      end
    end

    for _, key in ipairs(sortedKeys(localeTable)) do
      if ref[key] == nil then
        issues[#issues + 1] = string.format("%s.%s: EXTRA (not present in enUS)", localeName, key)
      end
    end
  end
end

if #issues == 0 then
  io.write("drift: clean — all locales aligned with enUS (keys + placeholders)\n")
  os.exit(0)
end

io.write(string.format("drift: %d issue(s) found\n\n", #issues))
for _, line in ipairs(issues) do
  io.write("  " .. line .. "\n")
end
os.exit(1)
