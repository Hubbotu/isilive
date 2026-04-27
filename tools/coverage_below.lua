#!/usr/bin/env lua
---@diagnostic disable: undefined-global
-- Lists every production file with coverage < THRESHOLD from luacov.report.out.
-- Usage: lua tools/coverage_below.lua [threshold] [report-path]
local threshold = tonumber(arg[1]) or 80
local path = arg[2] or "luacov.report.out"

local fh = assert(io.open(path, "r"))
local lines = {}
for line in fh:lines() do
  lines[#lines + 1] = line
end
fh:close()

local startIdx
for i = #lines, 1, -1 do
  if lines[i]:match("^Summary$") then
    startIdx = i
    break
  end
end
assert(startIdx, "no Summary block")

local entries = {}
for i = startIdx, #lines do
  local line = lines[i]
  local file, hits, missed, pct = line:match("^(.-)%s+(%d+)%s+(%d+)%s+([%d%.]+)%%$")
  if file and file:lower() ~= "total" and not file:match("^File") then
    entries[#entries + 1] = {
      file = (file:gsub("\\", "/")):gsub("%s+$", ""),
      hits = tonumber(hits),
      missed = tonumber(missed),
      pct = tonumber(pct),
    }
  end
end

table.sort(entries, function(a, b)
  return a.pct < b.pct
end)

io.write(string.format("Files below %.2f%% coverage:\n\n", threshold))
io.write("| File | Coverage | Hits | Missed |\n")
io.write("|---|---:|---:|---:|\n")
local count = 0
for _, e in ipairs(entries) do
  if e.pct < threshold then
    io.write(string.format("| %s | %.2f%% | %d | %d |\n", e.file, e.pct, e.hits, e.missed))
    count = count + 1
  end
end
io.write(string.format("\nTotal: %d files below %.0f%%\n", count, threshold))

-- Exit non-zero when at least one file is below the threshold, so this
-- script can be wired straight into CI as a gate (e.g. .github/workflows/
-- lua-check.yml's "Coverage Threshold" step). Pass-through 0 keeps it
-- usable as a list-only command for local inspection too — the count
-- line above tells the caller whether the gate would fail.
if count > 0 then
  os.exit(1)
end
