local RegisterFactoryPrimaryHighlightTests = dofile("testmodul/isilive_test_scenarios_factory_primary_part1.lua")

return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules
  local WithGlobals = ctx.with_globals

  RegisterFactoryPrimaryHighlightTests(test, Assert, LoadAddonModules, WithGlobals)
  require("testmodul.isilive_test_scenarios_factory_primary_part2")(test, ctx)
end
