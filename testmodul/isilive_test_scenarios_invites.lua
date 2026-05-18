---@diagnostic disable: undefined-global

local unpack = rawget(_G, "unpack") or rawget(table, "unpack")

local helpersChunk, helpersErr = loadfile("testmodul/isilive_test_ui_helpers.lua")
if not helpersChunk then
  error(helpersErr)
end
local UIHelpers = helpersChunk()
local BuildCreateFrameStub = UIHelpers.BuildCreateFrameStub

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

  test("Invites list keeps a sparse invited row when Blizzard search details are delayed", function()
    local controller = CreateController(LoadAddonModules, {})

    Assert.True(controller.HandleApplicationStatus(102, "invited"), "invited event with ID is a valid source")
    local invites = controller.GetOpenInvites()

    Assert.Equal(#invites, 1, "sparse invite row must still be listed")
    Assert.Equal(invites[1].searchResultID, 102, "searchResultID must be enough for accept/decline targeting")
    Assert.Nil(invites[1].dungeonName, "missing search-result details must not guess dungeon")
    Assert.Nil(invites[1].level, "missing search-result details must not guess level")
    Assert.Nil(invites[1].role, "missing search-result details must not guess role")
  end)

  test("Invites list enriches a sparse row when Blizzard search details arrive later", function()
    local searchResults = {}
    local controller = CreateController(LoadAddonModules, searchResults)

    controller.HandleApplicationStatus(103, "invited")
    searchResults[103] = { activityID = 1542, name = "+13 late", role = "HEALER" }
    controller.HandleApplicationStatus(103, "invited")
    local invites = controller.GetOpenInvites()

    Assert.Equal(#invites, 1, "late details must update the existing row instead of duplicating it")
    Assert.Equal(invites[1].dungeonName, "Windrunner Spire", "late activity map must fill dungeon name")
    Assert.Equal(invites[1].level, 13, "late title must fill numeric level")
    Assert.Equal(invites[1].role, "HEALER", "late role must fill role")
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

  test("Invites controller rejects invalid statuses and failed Blizzard calls", function()
    local controller = CreateController(LoadAddonModules, {
      [901] = { activityID = 1542, name = "+10 guarded" },
    }, {
      applications = "bad",
    })

    Assert.False(controller.HandleApplicationStatus(901, nil), "nil status must be rejected")
    Assert.False(controller.HandleApplicationStatus(901, ""), "blank status must be rejected")
    Assert.False(controller.HandleApplicationStatus(901, "applied"), "non-invite status must be ignored")
    Assert.False(controller.HandleApplicationStatus(0, "invited"), "invalid searchResultID must be rejected")
    Assert.True(controller.HandleApplicationStatus(902, "invited"), "valid invited status may create a sparse row")
    Assert.False(controller.RehydrateFromBlizzard(), "wrong-type application list must fail closed")
    Assert.False(controller.Accept(nil), "accept without searchResultID must fail")
    Assert.False(controller.Decline(nil), "decline without searchResultID must fail")
  end)

  test("Invites controller keeps subscribers isolated and clears once", function()
    local controller = CreateController(LoadAddonModules, {
      [910] = { activityID = 1542, name = "+10 one" },
    })
    local calls = 0
    local lastCount = nil
    local unsubscribe = controller.Subscribe(function(invites)
      calls = calls + 1
      lastCount = #invites
    end)

    Assert.Equal(calls, 1, "subscribe must receive the initial snapshot")
    Assert.Equal(lastCount, 0, "initial snapshot must be empty")
    controller.HandleApplicationStatus(910, "invited")
    Assert.Equal(lastCount, 1, "subscriber must receive added invite")
    Assert.True(controller.ClearAll(), "clear all must report removed rows")
    Assert.Equal(lastCount, 0, "subscriber must receive cleared list")
    Assert.False(controller.ClearAll(), "second clear must report no change")
    unsubscribe()
    controller.HandleApplicationStatus(910, "invited")
    Assert.Equal(calls, 3, "unsubscribed callback must not be called again")

    local noopUnsubscribe = controller.Subscribe(nil)
    Assert.Equal(type(noopUnsubscribe), "function", "non-function subscriber must return a no-op unsubscribe")
    noopUnsubscribe()
  end)

  test("Invites controller handles tuple application snapshots and guarded actions", function()
    local addon = LoadAddonModules({ "isiLive_invites.lua" })
    local acceptedCalls = 0
    local declinedCalls = 0
    local controller = addon.Invites.CreateController({
      getSearchResultInfo = function(searchResultID)
        return ({
          [920] = { activityIDs = { 1542, 1542 }, name = "|Kk123|k", selectedRole = "tank" },
          [921] = { activityIDs = { 1542, 1584 }, name = "+11 ambiguous" },
          [922] = { primaryActivityID = 1584, name = "11+", desiredRole = "healer", comment = "" },
        })[searchResultID]
      end,
      getApplications = function()
        return { 1, 2, 3 }
      end,
      getApplicationInfo = function(appID)
        if appID == 1 then
          return "invited", { resultID = 920, assignedRole = "damager" }
        end
        if appID == 2 then
          return { searchResultID = 921, applicationStatus = "invited" }
        end
        return 922, "invited"
      end,
      acceptInvite = function(searchResultID)
        acceptedCalls = acceptedCalls + 1
        return searchResultID ~= 920
      end,
      declineInvite = function(searchResultID)
        declinedCalls = declinedCalls + 1
        if searchResultID == 922 then
          error("decline failed")
        end
        return true
      end,
      resolveMapIDByActivityID = function(activityID)
        return ({ [1542] = 557, [1584] = 504 })[activityID]
      end,
      getDungeonName = function(mapID)
        if mapID == 557 then
          return ""
        end
        return ({ [504] = "Darkflame Cleft" })[mapID]
      end,
    })

    Assert.True(controller.RehydrateFromBlizzard(), "tuple applications must rehydrate open invites")
    local invites = controller.GetOpenInvites()
    Assert.Equal(#invites, 3, "all invited tuple snapshots must be represented")
    Assert.Equal(invites[1].levelText, "|Kk123|k", "keystone markup title must remain explicit level text")
    Assert.Equal(invites[1].role, "DAMAGER", "application role must override search-result role")
    Assert.Nil(invites[1].dungeonName, "empty dungeon-name lookup must remain unresolved")
    Assert.Nil(invites[2].mapID, "ambiguous activityIDs must fail closed")
    Assert.Equal(invites[3].level, 11, "reverse title-level markup must parse")

    Assert.False(controller.Accept(920), "failed accept must leave list open")
    Assert.Equal(acceptedCalls, 1, "failed accept must still target selected searchResultID")
    Assert.Equal(#controller.GetOpenInvites(), 3, "failed accept must not clear invites")
    Assert.False(controller.Decline(922), "decline pcall failure must return false")
    Assert.Equal(declinedCalls, 1, "decline must target selected searchResultID")
    Assert.True(controller.HandleApplicationStatus(920, "accepted"), "accepted status must clear all")
    Assert.Equal(#controller.GetOpenInvites(), 0, "accepted status must clear open invites")
  end)

  test("Invite list UI renders rows, caps visible entries, and targets clicked IDs", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local accepted = {}
    local declined = {}
    local parent = { _name = "UIParent" }

    ctx.with_globals({
      CreateFrame = createFrameStub,
      UIParent = parent,
    }, function()
      local addon = LoadAddonModules({ "isiLive_invite_list.lua" })
      local view = addon.InviteList.Create({
        parent = parent,
        getL = function()
          return {
            INVITE_LIST_TITLE = "Invites",
            INVITE_LIST_ACCEPT = "Join",
            INVITE_LIST_DECLINE = "No",
            INVITE_LIST_ROLE_FMT = "Role=%s",
            ROLE_NAME_TANK = "Tank",
            ROLE_NAME_HEALER = "Heal",
            ROLE_NAME_DAMAGE = "DPS",
          }
        end,
        onAccept = function(searchResultID)
          accepted[#accepted + 1] = searchResultID
        end,
        onDecline = function(searchResultID)
          declined[#declined + 1] = searchResultID
        end,
      })

      view.Render({
        {
          searchResultID = 1001,
          dungeonName = "Windrunner Spire",
          level = 12,
          groupName = "+12 chill",
          comment = "no leavers",
          role = "TANK",
        },
        { searchResultID = 1002, dungeonName = "Darkflame Cleft", role = "HEALER" },
        { searchResultID = 1003, levelText = "|Kk123|k", role = "DAMAGER" },
        { searchResultID = 1004, groupName = "Manual title" },
        { searchResultID = 1005 },
        { searchResultID = 1006, dungeonName = "Hidden sixth" },
      })

      Assert.True(view.frame:IsShown(), "invite list must show when invites are present")
      Assert.Equal(view.frame:GetHeight(), 46 + (5 * (52 + 4)), "height must cap at five visible rows")
      local titleText = view.frame._fontStrings[1]
      Assert.Equal(titleText:GetText(), "Invites", "title must use localized text")

      local firstRow = createdFrames[2]
      local firstAccept = createdFrames[3]
      local firstDecline = createdFrames[4]
      Assert.Equal(firstRow.primary:GetText(), "Windrunner Spire +12", "primary text must combine dungeon and level")
      Assert.Equal(firstRow.meta:GetText(), "+12 chill  |  Role=Tank", "meta must combine group title and role")
      Assert.Equal(firstRow.comment:GetText(), "no leavers", "comment must render explicit Blizzard text")
      Assert.Equal(firstAccept:GetText(), "Join", "accept label must localize")
      Assert.Equal(firstDecline:GetText(), "No", "decline label must localize")
      firstAccept._scripts.OnClick(firstAccept)
      firstDecline._scripts.OnClick(firstDecline)
      Assert.Equal(accepted[1], 1001, "accept click must target row searchResultID")
      Assert.Equal(declined[1], 1001, "decline click must target row searchResultID")

      Assert.Equal(createdFrames[5].primary:GetText(), "Darkflame Cleft", "dungeon-only row must render dungeon")
      Assert.Equal(createdFrames[8].primary:GetText(), "|Kk123|k", "levelText-only row must render level text")
      Assert.Equal(createdFrames[11].primary:GetText(), "Manual title", "group-title row must render group name")
      Assert.Equal(createdFrames[14].primary:GetText(), "LFG invite", "empty row must use neutral fallback")
      view.Render({})
      Assert.False(view.frame:IsShown(), "invite list must hide when no invites remain")
    end)
  end)

  test("Invite list UI stays hidden while the settings toggle is disabled", function()
    local createFrameStub = BuildCreateFrameStub()
    local parent = { _name = "UIParent" }
    local enabled = false

    ctx.with_globals({
      CreateFrame = createFrameStub,
      UIParent = parent,
    }, function()
      local addon = LoadAddonModules({ "isiLive_invite_list.lua" })
      local view = addon.InviteList.Create({
        parent = parent,
        isEnabled = function()
          return enabled
        end,
      })

      view.Render({ { searchResultID = 1001, dungeonName = "Windrunner Spire" } })
      Assert.False(view.frame:IsShown(), "disabled invite-list setting must keep the window hidden")

      enabled = true
      view.Render({ { searchResultID = 1001, dungeonName = "Windrunner Spire" } })
      Assert.True(view.frame:IsShown(), "re-enabled invite-list setting should render open invites")
    end)
  end)

  test("Invite list UI anchors to visible Blizzard invite surfaces and repositions on update", function()
    local createFrameStub = BuildCreateFrameStub()
    local parent = { _name = "UIParent" }
    local dialog = {
      IsShown = function()
        return true
      end,
    }

    ctx.with_globals({
      CreateFrame = createFrameStub,
      UIParent = parent,
      LFGListInviteDialog = dialog,
    }, function()
      local addon = LoadAddonModules({ "isiLive_invite_list.lua" })
      local view = addon.InviteList.Create({ parent = parent })
      view.Render({ { searchResultID = 2001, level = 7 } })
      local point, relativeTo, relativePoint, x, y = view.frame:GetPoint()

      Assert.Equal(point, "TOP", "dialog anchor point must be top")
      Assert.Equal(relativeTo, dialog, "visible LFG dialog must anchor invite list")
      Assert.Equal(relativePoint, "BOTTOM", "dialog anchor must attach below the Blizzard dialog")
      Assert.Equal(x, 0, "dialog x offset must be stable")
      Assert.Equal(y, -8, "dialog y offset must be stable")

      view.frame._scripts.OnUpdate(view.frame, 0.19)
      Assert.Equal(view.frame._positionElapsed, 0.19, "small elapsed updates must accumulate")
      view.frame._scripts.OnUpdate(view.frame, 0.01)
      Assert.Equal(view.frame._positionElapsed, 0, "position timer must reset after refresh")
    end)
  end)

  test("Invite list UI can anchor to static popup and ignores nil click callbacks", function()
    local createFrameStub, createdFrames = BuildCreateFrameStub()
    local parent = { _name = "UIParent" }
    local popup = {
      IsShown = function()
        return true
      end,
    }

    ctx.with_globals({
      CreateFrame = createFrameStub,
      UIParent = parent,
      StaticPopup1 = popup,
    }, function()
      local addon = LoadAddonModules({ "isiLive_invite_list.lua" })
      local view = addon.InviteList.Create({ parent = parent })
      view.Render({ { searchResultID = 3001, role = "NOPE" } })
      local _, relativeTo = view.frame:GetPoint()
      Assert.Equal(relativeTo, popup, "visible static popup must anchor invite list when LFG dialog is absent")

      local firstAccept = createdFrames[3]
      local firstDecline = createdFrames[4]
      firstAccept._scripts.OnClick(firstAccept)
      firstDecline._scripts.OnClick(firstDecline)
      firstAccept.searchResultID = nil
      firstDecline.searchResultID = nil
      firstAccept._scripts.OnClick(firstAccept)
      firstDecline._scripts.OnClick(firstDecline)
    end)
  end)
end
