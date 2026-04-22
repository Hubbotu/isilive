#!/usr/bin/env lua
---@diagnostic disable: undefined-global
-- Parses a luacov report and emits a GitHub Actions step summary.

-- Lua 5.1 exposes `unpack` as a global; 5.2+ moved it to `table.unpack`. CI
-- runs on 5.1, local dev can run 5.4; resolve both.
local Unpack = rawget(_G, "unpack") or (type(table) == "table" and rawget(table, "unpack"))
--
-- Reads luacov.report.out (or the path given as argv[1]) and writes a
-- Markdown summary to stdout: total coverage plus a per-layer breakdown
-- (core / locale / game / logic / factory / ui) and the ten least-covered
-- files so reviewers see trends without downloading the full artifact.

local function ReadLines(path)
  local fh, err = io.open(path, "r")
  if not fh then
    io.stderr:write(string.format("cannot open %s: %s\n", path, tostring(err)))
    os.exit(1)
  end
  local lines = {}
  for line in fh:lines() do
    lines[#lines + 1] = line
  end
  fh:close()
  return lines
end

-- The luacov report ends with a summary block:
--   Summary
--   =======
--
--   File                                   Hits Missed Coverage
--   ----
--   <file>                                 <hits> <missed> <pct>%
--   ...
--   ----
--   Total                                  <hits> <missed> <pct>%
local function ExtractSummaryBlock(lines)
  local startIdx
  for i = #lines, 1, -1 do
    if lines[i]:match("^Summary$") then
      startIdx = i
      break
    end
  end
  if not startIdx then
    return nil
  end
  return { Unpack(lines, startIdx) }
end

local function NormalizePath(raw)
  return (raw:gsub("\\", "/"))
end

local function ParseFileLine(line)
  -- Columns are whitespace-padded; last three tokens are Hits / Missed / Pct%.
  local file, hits, missed, pct = line:match("^(.-)%s+(%d+)%s+(%d+)%s+([%d%.]+)%%$")
  if not file then
    return nil
  end
  return {
    file = NormalizePath((file:gsub("%s+$", ""))),
    hits = tonumber(hits),
    missed = tonumber(missed),
    pct = tonumber(pct),
  }
end

local function ParseSummary(block)
  local files = {}
  local total
  for _, line in ipairs(block) do
    local trimmed = line:match("^%s*(.-)%s*$")
    local isBlankOrDivider = trimmed == "" or trimmed:match("^%-+$") or trimmed:match("^=+$")
    local isHeader = trimmed:match("^Summary$") or trimmed:match("^File%s")
    if not isBlankOrDivider and not isHeader then
      local entry = ParseFileLine(trimmed)
      if entry then
        if entry.file:lower() == "total" then
          total = entry
        else
          files[#files + 1] = entry
        end
      end
    end
  end
  return files, total
end

local LAYER_ORDER = { "core", "locale", "game", "logic", "factory", "ui" }

local function LayerOf(file)
  local layer = file:match("^([^/]+)/")
  if not layer then
    return "root"
  end
  return layer
end

local function AggregateByLayer(files)
  local layers = {}
  for _, entry in ipairs(files) do
    local layer = LayerOf(entry.file)
    local bucket = layers[layer] or { hits = 0, missed = 0 }
    bucket.hits = bucket.hits + entry.hits
    bucket.missed = bucket.missed + entry.missed
    layers[layer] = bucket
  end
  for _, bucket in pairs(layers) do
    local total = bucket.hits + bucket.missed
    bucket.pct = total > 0 and (bucket.hits / total) * 100 or 0
  end
  return layers
end

local function LeastCovered(files, limit)
  local copy = {}
  for i, entry in ipairs(files) do
    copy[i] = entry
  end
  table.sort(copy, function(a, b)
    if a.pct == b.pct then
      return a.file < b.file
    end
    return a.pct < b.pct
  end)
  local result = {}
  for i = 1, math.min(limit, #copy) do
    result[i] = copy[i]
  end
  return result
end

local path = arg and arg[1] or "luacov.report.out"
local lines = ReadLines(path)
local block = ExtractSummaryBlock(lines)
if not block then
  io.stderr:write("luacov report did not contain a Summary block\n")
  os.exit(1)
end

local files, total = ParseSummary(block)
if not total then
  io.stderr:write("luacov report did not contain a Total row\n")
  os.exit(1)
end

local layers = AggregateByLayer(files)

io.write("## Coverage Report\n\n")
io.write(
  string.format(
    "**Overall: %.2f%%** (%d lines covered / %d total)\n\n",
    total.pct,
    total.hits,
    total.hits + total.missed
  )
)

io.write("### By layer\n\n")
io.write("| Layer | Coverage | Lines |\n")
io.write("|---|---:|---:|\n")
for _, layer in ipairs(LAYER_ORDER) do
  local bucket = layers[layer]
  if bucket then
    io.write(
      string.format("| `%s/` | %.2f%% | %d / %d |\n", layer, bucket.pct, bucket.hits, bucket.hits + bucket.missed)
    )
  end
end
if layers.root then
  io.write(
    string.format(
      "| (root) | %.2f%% | %d / %d |\n",
      layers.root.pct,
      layers.root.hits,
      layers.root.hits + layers.root.missed
    )
  )
end

io.write("\n### Ten least-covered files\n\n")
io.write("| File | Coverage | Missed |\n")
io.write("|---|---:|---:|\n")
for _, entry in ipairs(LeastCovered(files, 10)) do
  io.write(string.format("| `%s` | %.2f%% | %d |\n", entry.file, entry.pct, entry.missed))
end
