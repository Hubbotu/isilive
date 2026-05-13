---@diagnostic disable: undefined-global, undefined-field

-- Scenarios for the small DB-resolver helpers exported via _FactoryInternal
-- from factory/isiLive_factory.lua. These are pure, tiny predicates used by
-- the composition root; they were never exercised by the existing factory
-- scenarios which only touch the orchestrator path.

local function Load(LoadAddonModules)
  return LoadAddonModules({ "isiLive_factory.lua" })
end

return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules

  test("factory resolvers: ResolveAutoCloseOnKeyStartEnabled defaults ON, opt-out via explicit false", function()
    local addon = Load(LoadAddonModules)
    local fn = addon._FactoryInternal.ResolveAutoCloseOnKeyStartEnabled
    Assert.Equal(fn(nil), true, "nil DB must default to enabled (default-ON since 0.9.238)")
    Assert.Equal(fn({}), true, "empty table must default to enabled")
    Assert.Equal(fn({ autoCloseOnKeyStart = false }), false, "explicit false opts the user out")
    Assert.Equal(
      fn({ autoCloseOnKeyStart = "false" }),
      true,
      "only strict boolean false opts out; non-boolean values keep the default"
    )
    Assert.Equal(fn({ autoCloseOnKeyStart = true }), true, "explicit true matches the default")
    Assert.Equal(fn("not-a-table"), true, "non-table input falls back to the default")
  end)

  test("factory resolvers: ResolveAutoCloseOnSoloChangeEnabled requires explicit true", function()
    local addon = Load(LoadAddonModules)
    local fn = addon._FactoryInternal.ResolveAutoCloseOnSoloChangeEnabled
    Assert.Equal(fn(nil), false, "nil DB must default to disabled")
    Assert.Equal(fn({}), false, "empty table must default to disabled")
    Assert.Equal(fn({ autoCloseOnSoloChange = false }), false)
    Assert.Equal(fn({ autoCloseOnSoloChange = true }), true)
  end)

  test("factory resolvers: ResolveAutoShowMainFrameOnStartupEnabled defaults true", function()
    local addon = Load(LoadAddonModules)
    local fn = addon._FactoryInternal.ResolveAutoShowMainFrameOnStartupEnabled
    Assert.Equal(fn(nil), true, "nil DB must default to enabled")
    Assert.Equal(fn({}), true)
    Assert.Equal(fn({ autoShowMainFrameOnStartup = true }), true)
    Assert.Equal(fn({ autoShowMainFrameOnStartup = false }), false, "explicit false disables")
    Assert.Equal(fn({ autoShowMainFrameOnStartup = "false" }), true, "only strict boolean false disables")
  end)

  test("factory resolvers: ResolveAutoOpenMainFrameOnKeyEndEnabled defaults true", function()
    local addon = Load(LoadAddonModules)
    local fn = addon._FactoryInternal.ResolveAutoOpenMainFrameOnKeyEndEnabled
    Assert.Equal(fn(nil), true)
    Assert.Equal(fn({}), true)
    Assert.Equal(fn({ autoOpenMainFrameOnKeyEnd = false }), false)
    Assert.Equal(fn({ autoOpenMainFrameOnKeyEnd = true }), true)
  end)

  test("factory resolvers: ResolveMainFramePositionLockEnabled defaults true", function()
    local addon = Load(LoadAddonModules)
    local fn = addon._FactoryInternal.ResolveMainFramePositionLockEnabled
    Assert.Equal(fn(nil), true, "nil DB must default to locked")
    Assert.Equal(fn({}), true, "empty table must default to locked")
    Assert.Equal(fn({ lockMainFramePosition = false }), false, "explicit false unlocks the frame")
    Assert.Equal(fn({ lockMainFramePosition = true }), true)
    Assert.Equal(fn({ lockMainFramePosition = 0 }), true, "only strict boolean false unlocks")
  end)

  test("factory resolvers: ResolveRaidTransitionBehavior always returns hide", function()
    local addon = Load(LoadAddonModules)
    local fn = addon._FactoryInternal.ResolveRaidTransitionBehavior
    Assert.Equal(fn(nil), "hide", "missing DB must default to hide")
    Assert.Equal(fn({}), "hide")
    Assert.Equal(fn({ raidTransitionBehavior = "show" }), "hide", "setting is intentionally frozen to hide")
    Assert.Equal(fn("not-a-table"), "hide")
  end)
end
