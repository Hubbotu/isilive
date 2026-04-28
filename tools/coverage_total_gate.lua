#!/usr/bin/env lua
---@diagnostic disable: undefined-global
-- Asserts the Total coverage line in luacov.report.out is at or above
-- THRESHOLD percent. Companion to coverage_below.lua, which gates the
-- per-file floor; this one gates the aggregate floor so coverage cannot
-- silently regress over time even if every individual file still
-- clears 80%.
--
-- Usage: lua tools/coverage_total_gate.lua [threshold] [report-path]
local threshold = tonumber(arg[1]) or 88
local path = arg[2] or "luacov.report.out"

local fh, err = io.open(path, "r")
if not fh then
  io.stderr:write(string.format("cannot open %s: %s\n", path, tostring(err)))
  os.exit(1)
end

local total
for line in fh:lines() do
  local hits, missed, pct = line:match("^Total%s+(%d+)%s+(%d+)%s+([%d%.]+)%%$")
  if hits then
    total = { hits = tonumber(hits), missed = tonumber(missed), pct = tonumber(pct) }
  end
end
fh:close()

if not total then
  io.stderr:write("luacov report did not contain a Total row\n")
  os.exit(1)
end

io.write(string.format("Total coverage: %.2f%% (gate: >=%.2f%%)\n", total.pct, threshold))

if total.pct < threshold then
  io.stderr:write(string.format("Total coverage %.2f%% is below the %.2f%% gate\n", total.pct, threshold))
  os.exit(1)
end
