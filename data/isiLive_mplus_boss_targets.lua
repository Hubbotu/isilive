-- Data derived from community source (GPLv2) by community —
-- https://github.com/community-source/forces-data (Data/Expansions/*.lua).
--
-- Per-dungeon cumulative Enemy-Forces-% targets, one entry per boss in
-- bossOrder sequence (i.e. the order Blizzard's scenario criteria list
-- presents them, which matches the order players encounter them). The
-- last value is always 100; any intermediate targets tell the player
-- "you should have at least X% forces before engaging the next boss".
--
-- User can override per-mapID values via:
--   IsiLiveDB.bossTargetsOverride = { [mapID] = { t1, t2, ... } }
-- (not wired into the UI yet — manual slash-command or lua edit).

local _, addonTable = ...

addonTable.MPlusBossTargets = {
  season = "midnight_s1",
  source = "community source 3.8 (Data/Expansions/*.lua)",
  generatedAt = "2026-04-24",

  -- Boss target percentages per challenge-mode mapID, ordered by bossOrder.
  byMapID = {
    [161] = { 28.07, 52.2, 60.09, 100 }, -- Skyreach
    [239] = { 14.61, 56.87, 100, 100 }, -- Seat of the Triumvirate
    [402] = { 21.52, 51.09, 77.17, 100 }, -- Algeth'ar Academy
    [556] = { 58.63, 79.94, 100 }, -- Pit of Saron
    [557] = { 45.35, 57.36, 100, 100 }, -- Windrunner Spire
    [558] = { 27.81, 48.91, 78.06, 100 }, -- Magisters' Terrace
    [559] = { 29.36, 73.66, 100 }, -- Nexus-Point Xenas
    [560] = { 48.6, 89.95, 100 }, -- Maisara Caverns
  },
}
