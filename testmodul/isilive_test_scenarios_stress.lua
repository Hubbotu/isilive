---@diagnostic disable: undefined-global

local function MakeStrsplit()
  return function(sep, str, max)
    local pos = str:find(sep, 1, true)
    if not pos then
      return str
    end
    if max and max >= 2 then
      return str:sub(1, pos - 1), str:sub(pos + 1)
    end
    return str:sub(1, pos - 1)
  end
end

local function RegisterLargeGroupSyncStormTests(test, Assert, WithGlobals, LoadAddonModules)
  test("Sync handles 40-player group sync storm without data loss", function()
    WithGlobals({
      strsplit = MakeStrsplit(),
      GetRealmName = function()
        return "Realm"
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_sync.lua" })

      local playerCount = 40
      local updatesPerPlayer = 5
      local totalExpectedKeys = playerCount

      for i = 1, playerCount do
        local sender = string.format("Player%d-Realm", i)
        for j = 1, updatesPerPlayer do
          addon.Sync.ProcessAddonMessage("ISILIVE", string.format("KEY:2649:%d", j), sender, "Me", "Realm")
          addon.Sync.ProcessAddonMessage("ISILIVE", string.format("STATS:72:%d:3000", 600 + j), sender, "Me", "Realm")
        end
      end

      local storedKeys = 0
      for i = 1, playerCount do
        local info = addon.Sync.GetPlayerKeyInfo(string.format("Player%d", i), "Realm")
        if info then
          storedKeys = storedKeys + 1
          Assert.Equal(info.level, updatesPerPlayer, string.format("Player%d must retain latest key level", i))
        end
      end
      Assert.Equal(storedKeys, totalExpectedKeys, "all 40 players must have stored key data")
    end)
  end)

  test("Sync rejects oversized payloads from all 40 group members", function()
    WithGlobals({
      strsplit = MakeStrsplit(),
      GetRealmName = function()
        return "Realm"
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_sync.lua" })

      local oversizedMessage = string.rep("A", 256)

      for i = 1, 40 do
        local result =
          addon.Sync.ProcessAddonMessage("ISILIVE", oversizedMessage, string.format("Player%d-Realm", i), "Me", "Realm")
        Assert.Nil(result, string.format("oversized payload from Player%d must be dropped", i))
      end

      for i = 1, 40 do
        Assert.Nil(
          addon.Sync.GetPlayerKeyInfo(string.format("Player%d", i), "Realm"),
          string.format("oversized payload must not store any data for Player%d", i)
        )
      end
    end)
  end)

  test("Sync handles empty and nil message payloads without error", function()
    WithGlobals({
      strsplit = MakeStrsplit(),
      GetRealmName = function()
        return "Realm"
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_sync.lua" })

      local emptyResult = addon.Sync.ProcessAddonMessage("ISILIVE", "", "Player1-Realm", "Me", "Realm")
      Assert.Nil(emptyResult, "empty message must be dropped")

      local nilResult = addon.Sync.ProcessAddonMessage("ISILIVE", nil, "Player1-Realm", "Me", "Realm")
      Assert.Nil(nilResult, "nil message must be dropped")

      local numericResult = addon.Sync.ProcessAddonMessage("ISILIVE", 12345, "Player1-Realm", "Me", "Realm")
      Assert.Nil(numericResult, "numeric message must be dropped")
    end)
  end)
end

local function RegisterRingBufferStressTests(test, Assert, WithGlobals, LoadAddonModules)
  test("RuntimeLog ring buffer stays capped under 10000-message burst from 40 players", function()
    WithGlobals({
      IsiLiveDB = {},
      GetTime = function()
        return 1000
      end,
      strsplit = MakeStrsplit(),
      GetRealmName = function()
        return "Realm"
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_log_buffer.lua", "isiLive_runtime_log.lua", "isiLive_sync.lua" })
      local runtimeLog = addon.RuntimeLog.CreateController({
        getTimestamp = function()
          return "1000.000"
        end,
        maxEntries = 100,
      })
      runtimeLog.SetEnabled(true)
      addon.Sync.SetTraceLogger(runtimeLog.Trace)

      for i = 1, 40 do
        local sender = string.format("Player%d-Realm", i)
        for j = 1, 250 do
          addon.Sync.ProcessAddonMessage("ISILIVE", string.format("KEY:2649:%d", j), sender, "Me", "Realm")
        end
      end

      Assert.Equal(runtimeLog.GetLogCount(), 100, "ring buffer must stay capped at maxEntries under heavy burst")
      local tail = runtimeLog.GetLogTail(100)
      Assert.Equal(#tail, 100, "tail must return exactly maxEntries entries")
    end)
  end)
end

local function RegisterNormalizeKeyStressTests(test, Assert, WithGlobals, LoadAddonModules)
  test("NormalizePlayerKey handles 1000 unique realm name variants without collision", function()
    WithGlobals({
      strsplit = MakeStrsplit(),
      GetRealmName = function()
        return "Realm"
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_sync.lua" })

      local seen = {}
      local collisions = 0

      local realmVariants = {
        "Dun Morogh",
        "Dun-Morogh",
        "DunMorogh",
        "Der Rat von Dalaran",
        "Der-Rat-von-Dalaran",
        "DerRatvonDalaran",
        "Azjol-Nerub",
        "AzjolNerub",
        "Aggra (Português)",
        "AggraPortugues",
        "Quel'Thalas",
        "QuelThalas",
      }

      for _, realm in ipairs(realmVariants) do
        local key = addon.Sync.NormalizePlayerKey("TestPlayer", realm)
        Assert.NotNil(key, "NormalizePlayerKey must return a non-nil key for realm: " .. realm)
        Assert.True(#key > 0, "NormalizePlayerKey must return a non-empty key")
      end

      for i = 1, 1000 do
        local name = string.format("Player%d", i)
        local key = addon.Sync.NormalizePlayerKey(name, "TestRealm")
        if seen[key] then
          collisions = collisions + 1
        end
        seen[key] = true
      end

      Assert.Equal(collisions, 0, "NormalizePlayerKey must produce unique keys for 1000 distinct player names")
    end)
  end)

  test("Sync ClearKnownUsers fully resets state after 40-player storm", function()
    WithGlobals({
      strsplit = MakeStrsplit(),
      GetRealmName = function()
        return "Realm"
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_sync.lua" })

      for i = 1, 40 do
        local sender = string.format("Player%d-Realm", i)
        addon.Sync.ProcessAddonMessage("ISILIVE", "KEY:2649:15", sender, "Me", "Realm")
        addon.Sync.ProcessAddonMessage("ISILIVE", "STATS:72:615:3000", sender, "Me", "Realm")
      end

      addon.Sync.ClearKnownUsers()

      for i = 1, 40 do
        Assert.Nil(
          addon.Sync.GetPlayerKeyInfo(string.format("Player%d", i), "Realm"),
          string.format("key info for Player%d must be nil after ClearKnownUsers", i)
        )
        Assert.Nil(
          addon.Sync.GetPlayerStatsInfo(string.format("Player%d", i), "Realm"),
          string.format("stats info for Player%d must be nil after ClearKnownUsers", i)
        )
        Assert.False(
          addon.Sync.IsUserKnown(string.format("Player%d", i), "Realm"),
          string.format("Player%d must not be known after ClearKnownUsers", i)
        )
      end
    end)
  end)
end

local function RegisterLibKeystoneValidationTests(test, Assert, WithGlobals, LoadAddonModules)
  test("Sync ProcessAddonMessage rejects oversized LibKeystone payloads", function()
    WithGlobals({
      strsplit = MakeStrsplit(),
      GetRealmName = function()
        return "Realm"
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_sync.lua" })

      local oversized = string.rep("1", 256)
      local result = addon.Sync.ProcessAddonMessage("LibKS", oversized, "Player-Realm", "Me", "Realm", "PARTY")
      Assert.Nil(result, "oversized LibKeystone payload must be dropped")

      local emptyResult = addon.Sync.ProcessAddonMessage("LibKS", "", "Player-Realm", "Me", "Realm", "PARTY")
      Assert.Nil(emptyResult, "empty LibKeystone payload must be dropped")
    end)
  end)

  test("Sync ProcessAddonMessage rejects LibKeystone payloads with negative level or mapID", function()
    WithGlobals({
      strsplit = MakeStrsplit(),
      GetRealmName = function()
        return "Realm"
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_sync.lua" })

      local negLevelResult =
        addon.Sync.ProcessAddonMessage("LibKS", "-5,2649,3000", "Player-Realm", "Me", "Realm", "PARTY")
      Assert.Nil(negLevelResult, "negative level LibKeystone payload must be dropped")
      Assert.Nil(addon.Sync.GetPlayerKeyInfo("Player", "Realm"), "negative level must not store key info")

      local negMapResult =
        addon.Sync.ProcessAddonMessage("LibKS", "15,-100,3000", "Player-Realm", "Me", "Realm", "PARTY")
      Assert.Nil(negMapResult, "negative mapID LibKeystone payload must be dropped")
      Assert.Nil(addon.Sync.GetPlayerKeyInfo("Player", "Realm"), "negative mapID must not store key info")
    end)
  end)

  test("Sync ProcessAddonMessage rejects LibKeystone payloads on non-PARTY channel", function()
    WithGlobals({
      strsplit = MakeStrsplit(),
      GetRealmName = function()
        return "Realm"
      end,
    }, function()
      local addon = LoadAddonModules({ "isiLive_sync.lua" })

      local guildResult =
        addon.Sync.ProcessAddonMessage("LibKS", "15,2649,3000", "Player-Realm", "Me", "Realm", "GUILD")
      Assert.Nil(guildResult, "LibKeystone payload on GUILD channel must be dropped")

      local raidResult = addon.Sync.ProcessAddonMessage("LibKS", "15,2649,3000", "Player-Realm", "Me", "Realm", "RAID")
      Assert.Nil(raidResult, "LibKeystone payload on RAID channel must be dropped")

      local partyResult =
        addon.Sync.ProcessAddonMessage("LibKS", "15,2649,3000", "Player-Realm", "Me", "Realm", "PARTY")
      Assert.NotNil(partyResult, "valid LibKeystone payload on PARTY channel must be accepted")
    end)
  end)
end

return function(test, ctx)
  local Assert = ctx.assert
  local WithGlobals = ctx.with_globals
  local LoadAddonModules = ctx.load_modules

  RegisterLargeGroupSyncStormTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterRingBufferStressTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterNormalizeKeyStressTests(test, Assert, WithGlobals, LoadAddonModules)
  RegisterLibKeystoneValidationTests(test, Assert, WithGlobals, LoadAddonModules)
end
