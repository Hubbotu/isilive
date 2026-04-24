---@diagnostic disable: undefined-global

-- Lua 5.1 / 5.4 compat: bridge unpack in both directions so test scenarios
-- run identically whether the host Lua is 5.1 (CI) or 5.4 (local).
-- Lua 5.1: table.unpack does not exist → set it from the global unpack.
-- Lua 5.4: the global unpack does not exist → set it from table.unpack.
-- rawget/rawset avoid luacheck "undefined field" warnings on both versions.
if type(rawget(table, "unpack")) ~= "function" and type(rawget(_G, "unpack")) == "function" then
  rawset(table, "unpack", rawget(_G, "unpack"))
end
if type(rawget(_G, "unpack")) ~= "function" and type(rawget(table, "unpack")) == "function" then
  rawset(_G, "unpack", rawget(table, "unpack"))
end

local loaderChunk, loaderErr = loadfile("testmodul/isilive_test_loader.lua")
if not loaderChunk then
  error(string.format("cannot load test loader: %s", tostring(loaderErr)))
end

local Loader = loaderChunk()
local Assert = Loader.LoadModule("testmodul/isilive_test_assert.lua")
local Harness = Loader.LoadModule("testmodul/isilive_test_harness.lua")
local Fixtures = Loader.LoadModule("testmodul/isilive_test_fixtures.lua")
local RulesValidator = Loader.LoadModule("tools/rules_logic_validator.lua")
local scenarioFiles = Loader.LoadModule("tools/usecase_scenarios.lua")

local runner = Harness.NewRunner()
local currentBeforeEach = nil
local test = {}
setmetatable(test, {
  __call = function(_, name, fn)
    runner.Test(name, fn)
  end,
})

function test.describe(_, fn)
  local parentBeforeEach = currentBeforeEach
  fn()
  currentBeforeEach = parentBeforeEach
end

function test.before_each(fn)
  currentBeforeEach = fn
end

function test.it(name, fn)
  local setup = currentBeforeEach
  runner.Test(name, function()
    if setup then
      setup()
    end
    fn()
  end)
end

if type(RulesValidator) ~= "table" or type(RulesValidator.Run) ~= "function" then
  error("rules logic validator module must return table with Run(opts)")
end
if type(scenarioFiles) ~= "table" then
  error("scenario manifest must return table")
end

local sharedTests, sharedTestErrors, sharedExpanded = RulesValidator.CollectTests(scenarioFiles)
if #sharedTestErrors > 0 then
  for _, err in ipairs(sharedTestErrors) do
    print("[FAIL] " .. err)
  end
  os.exit(1)
end

local rulesOk = RulesValidator.Run({
  rulesPath = "docs/RULES_LOGIC.md",
  scenarioFiles = scenarioFiles,
  testsByName = sharedTests,
  expandedScenarioFiles = sharedExpanded,
  printFn = print,
})
if not rulesOk then
  os.exit(1)
end

local architectureRulesOk = RulesValidator.Run({
  rulesPath = "docs/ARCHITECTURE_RULES.md",
  scenarioFiles = scenarioFiles,
  testsByName = sharedTests,
  expandedScenarioFiles = sharedExpanded,
  printFn = print,
})
if not architectureRulesOk then
  os.exit(1)
end

local context = {
  assert = Assert,
  with_globals = Harness.WithGlobals,
  load_modules = Harness.LoadAddonModules,
  fixtures = Fixtures,
}

for _, file in ipairs(scenarioFiles) do
  local register = Loader.LoadModule(file)
  if type(register) ~= "function" then
    error(string.format("scenario module must return register function: %s", file))
  end
  register(test, context)
end

print(string.format("Loaded %d usecase scenarios from %d modules", runner.GetCount(), #scenarioFiles))

local _, failed = runner.Run()
if failed > 0 then
  os.exit(1)
end

os.exit(0)
