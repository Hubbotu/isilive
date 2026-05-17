---@diagnostic disable: undefined-global

local unpack = rawget(_G, "unpack") or rawget(table, "unpack")

local function CreateController(LoadAddonModules, searchResults, opts)
  opts = opts or {}
  local addon = LoadAddonModules({ "isiLive_invites.lua" })
  local applications = opts.applications or {}
  local applicationInfo = opts.applicationInfo or {}
  local accepted = {}
  local declined = {}
  local controller = addon.Invites.CreateController({
    getSearchResultInfo = function(searchResultID)
      return searchResults[searchResultID]
    end,
    getApplications = function()
      return applications
    end,
    getApplicationInfo = function(applicationID)
      local value = applicationInfo[applicationID]
      if type(value) == "table" and value.__tuple then
        return unpack(value)
      end
      return value
    end,
    acceptInvite = function(searchResultID)
      table.insert(accepted, searchResultID)
    end,
    declineInvite = function(searchResultID)
      table.insert(declined, searchResultID)
    end,
    resolveMapIDByActivityID = function(activityID)
      return ({ [1542] = 557, [1584] = 504 })[activityID]
    end,
    getDungeonName = function(mapID)
      return ({ [557] = "Windrunner Spire", [504] = "Darkflame Cleft" })[mapID]
    end,
  })
  return controller, accepted, declined
end

return function(test, ctx)
  local Assert = ctx.assert
  local LoadAddonModules = ctx.load_modules

  test("Invites list adds one verified LFG invite from invited status", function()
    local controller = CreateController(LoadAddonModules, {
      [101] = {
        activityID = 1542,
        name = "+12 chill",
        comment = "no leavers",
        leaderName = "Lead",
        role = "DAMAGER",
      },
    })

    controller.HandleApplicationStatus(101, "invited")
    local invites = controller.GetOpenInvites()

    Assert.Equal(#invites, 1, "one open invite must be listed")
    Assert.Equal(invites[1].searchResultID, 101, "searchResultID must be preserved")
    Assert.Equal(invites[1].dungeonName, "Windrunner Spire", "verified activity map must drive dungeon name")
    Assert.Equal(invites[1].level, 12, "numeric key level must be parsed from title")
    Assert.Equal(invites[1].comment, "no leavers", "leader comment must be preserved")
    Assert.Equal(invites[1].role, "DAMAGER", "explicit invite role must be preserved")
  end)

  test("Invites list orders multiple open invites chronologically", function()
    local controller = CreateController(LoadAddonModules, {
      [201] = { activityID = 1542, name = "+10 first" },
      [202] = { activityID = 1584, name = "+11 second" },
    })

    controller.HandleApplicationStatus(201, "invited")
    controller.HandleApplicationStatus(202, "invited")
    local invites = controller.GetOpenInvites()

    Assert.Equal(#invites, 2, "both invites must stay visible")
    Assert.Equal(invites[1].searchResultID, 201, "first invite must stay first")
    Assert.Equal(invites[2].searchResultID, 202, "second invite must stay second")
  end)

  test("Invites list deduplicates duplicate invited events by searchResultID", function()
    local controller = CreateController(LoadAddonModules, {
      [301] = { activityID = 1542, name = "+9 first" },
    })

    controller.HandleApplicationStatus(301, "invited")
    controller.HandleApplicationStatus(301, "invited")

    Assert.Equal(#controller.GetOpenInvites(), 1, "duplicate invited event must not create a second row")
  end)

  test("Invites list removes only the declined invite", function()
    local controller = CreateController(LoadAddonModules, {
      [401] = { activityID = 1542, name = "+8 one" },
      [402] = { activityID = 1584, name = "+9 two" },
    })

    controller.HandleApplicationStatus(401, "invited")
    controller.HandleApplicationStatus(402, "invited")
    controller.HandleApplicationStatus(401, "declined")
    local invites = controller.GetOpenInvites()

    Assert.Equal(#invites, 1, "decline must remove one row")
    Assert.Equal(invites[1].searchResultID, 402, "unrelated invite must remain")
  end)

  test("Invites list clears all open invites after accepting one invite", function()
    local controller, accepted = CreateController(LoadAddonModules, {
      [501] = { activityID = 1542, name = "+8 one" },
      [502] = { activityID = 1584, name = "+9 two" },
    })

    controller.HandleApplicationStatus(501, "invited")
    controller.HandleApplicationStatus(502, "invited")
    local acceptedOk = controller.Accept(502)

    Assert.True(acceptedOk, "accept action must report success when Blizzard call succeeds")
    Assert.Equal(accepted[1], 502, "accept action must target the selected searchResultID")
    Assert.Equal(#controller.GetOpenInvites(), 0, "accepted invite must close the open invite list")
  end)

  test("Invites list decline button path removes the selected invite", function()
    local controller, _, declined = CreateController(LoadAddonModules, {
      [601] = { activityID = 1542, name = "+8 one" },
      [602] = { activityID = 1584, name = "+9 two" },
    })

    controller.HandleApplicationStatus(601, "invited")
    controller.HandleApplicationStatus(602, "invited")
    local declinedOk = controller.Decline(601)

    Assert.True(declinedOk, "decline action must report success when Blizzard call succeeds")
    Assert.Equal(declined[1], 601, "decline action must target the selected searchResultID")
    Assert.Equal(#controller.GetOpenInvites(), 1, "decline action must leave other invites open")
  end)

  test("Invites list rehydrates invited applications after reload", function()
    local controller = CreateController(LoadAddonModules, {
      [701] = { activityID = 1542, name = "+14 rehydrated", role = "HEALER" },
    }, {
      applications = { 9001 },
      applicationInfo = {
        [9001] = {
          searchResultID = 701,
          applicationStatus = "invited",
          role = "HEALER",
        },
      },
    })

    controller.RehydrateFromBlizzard()
    local invites = controller.GetOpenInvites()

    Assert.Equal(#invites, 1, "invited application must rehydrate")
    Assert.Equal(invites[1].searchResultID, 701, "rehydrated invite must keep searchResultID")
    Assert.Equal(invites[1].role, "HEALER", "rehydrated role must come from application data")
  end)

  test("Invites list keeps missing role and unresolved dungeon empty instead of guessing", function()
    local controller = CreateController(LoadAddonModules, {
      [801] = { activityID = 9999, name = "Windrunner Spire" },
    })

    controller.HandleApplicationStatus(801, "invited")
    local invites = controller.GetOpenInvites()

    Assert.Equal(#invites, 1, "invite row may exist without resolved dungeon")
    Assert.Nil(invites[1].dungeonName, "unresolved activity must not guess dungeon from title")
    Assert.Nil(invites[1].mapID, "unresolved activity must keep mapID empty")
    Assert.Nil(invites[1].role, "missing role must stay empty")
  end)
end
