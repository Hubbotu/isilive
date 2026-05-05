local _, addonTable = ...

addonTable = addonTable or {}

local SoundUtils = {}
addonTable.SoundUtils = SoundUtils

local SPAM_WINDOW = 1.0 -- seconds: ignore duplicate sound within this window
local lastPlayedAt = {} -- soundKey -> timestamp

SoundUtils.Registry = {
  leader_transfer = {
    file = "Interface\\AddOns\\isiLive\\sounds\\CartoonVoiceBaritone.ogg",
    labelKey = "SETTINGS_SOUND_LEAD_ENABLED",
    settingKey = "soundLeadEnabled",
    defaultEnabled = true,
    defaultChannel = "SFX",
  },
  group_join = {
    file = "Interface\\AddOns\\isiLive\\sounds\\SynthChord.ogg",
    labelKey = "SETTINGS_SOUND_GROUP_JOIN_ENABLED",
    settingKey = "soundGroupJoinEnabled",
    defaultEnabled = true,
    defaultChannel = "SFX",
  },
  portal_available = {
    -- Resolved via SOUNDKIT[name] at play time so the registry entry stays
    -- portable across patches even if Blizzard renames the constant.
    soundKit = "UI_GROUP_FINDER_RECEIVE_APPLICATION",
    labelKey = "SETTINGS_SOUND_PORTAL_AVAILABLE",
    settingKey = "soundPortalAvailableEnabled",
    defaultEnabled = true,
    defaultChannel = "SFX",
  },
  battle_res = {
    file = "Interface\\AddOns\\isiLive\\sounds\\ChickenAlarm.ogg",
    labelKey = "SETTINGS_SOUND_BATTLE_RES",
    settingKey = "soundBattleResEnabled",
    defaultEnabled = true,
    defaultChannel = "SFX",
  },
  bloodlust = {
    file = "Interface\\AddOns\\isiLive\\sounds\\BoxingArenaSound.ogg",
    labelKey = "SETTINGS_SOUND_BLOODLUST",
    settingKey = "soundBloodlustEnabled",
    defaultEnabled = true,
    defaultChannel = "SFX",
  },
}

SoundUtils.SettingsOrder = {
  "leader_transfer",
  "group_join",
  "portal_available",
  "battle_res",
  "bloodlust",
}

local function BuildSoundKey(soundFile, channel)
  return tostring(soundFile) .. "\31" .. tostring(channel or "SFX")
end

function SoundUtils.GetEntry(key)
  if type(key) ~= "string" or key == "" then
    return nil
  end
  local registry = SoundUtils.Registry
  if type(registry) ~= "table" then
    return nil
  end
  local entry = registry[key]
  if type(entry) ~= "table" then
    return nil
  end
  return entry
end

function SoundUtils.HasKey(key)
  return SoundUtils.GetEntry(key) ~= nil
end

function SoundUtils.IsEnabled(key)
  local entry = SoundUtils.GetEntry(key)
  if not entry then
    return false
  end

  local db = rawget(_G, "IsiLiveDB")
  local settingKey = type(entry.settingKey) == "string" and entry.settingKey or nil
  if settingKey and type(db) == "table" then
    local stored = db[settingKey]
    if stored ~= nil then
      return stored == true
    end
  end

  return entry.defaultEnabled ~= false
end

-- Plays a sound file on the SFX channel with spam protection.
-- A sound that was played less than SPAM_WINDOW seconds ago is silently dropped.
function SoundUtils.Play(soundFile, channel)
  if type(soundFile) ~= "string" or soundFile == "" then
    return
  end
  local resolvedChannel = type(channel) == "string" and channel ~= "" and channel or "SFX"
  local GetTime_ref = rawget(_G, "GetTime")
  local now = type(GetTime_ref) == "function" and GetTime_ref() or 0
  local soundKey = BuildSoundKey(soundFile, resolvedChannel)
  local last = lastPlayedAt[soundKey]
  if last and (now - last) < SPAM_WINDOW then
    return
  end
  lastPlayedAt[soundKey] = now
  local playSoundFile = rawget(_G, "PlaySoundFile")
  if type(playSoundFile) == "function" then
    playSoundFile(soundFile, resolvedChannel)
  end
end

-- Plays a Blizzard SoundKit (numeric ID or SOUNDKIT name) with spam protection
-- on the same window as Play() above. Silently no-ops when the kit name does
-- not resolve in this client (e.g. constant renamed in a future patch).
function SoundUtils.PlaySoundKit(soundKit, channel)
  if soundKit == nil then
    return
  end
  local resolvedKit = soundKit
  if type(resolvedKit) == "string" then
    local kitTable = rawget(_G, "SOUNDKIT")
    resolvedKit = type(kitTable) == "table" and kitTable[soundKit] or nil
  end
  if resolvedKit == nil then
    return
  end
  local resolvedChannel = type(channel) == "string" and channel ~= "" and channel or "SFX"
  local GetTime_ref = rawget(_G, "GetTime")
  local now = type(GetTime_ref) == "function" and GetTime_ref() or 0
  local soundKey = "kit\31" .. tostring(resolvedKit) .. "\31" .. resolvedChannel
  local last = lastPlayedAt[soundKey]
  if last and (now - last) < SPAM_WINDOW then
    return
  end
  lastPlayedAt[soundKey] = now
  local playSound = rawget(_G, "PlaySound")
  if type(playSound) == "function" then
    playSound(resolvedKit, resolvedChannel)
  end
end

function SoundUtils.PlayKey(key)
  local entry = SoundUtils.GetEntry(key)
  if not entry or not SoundUtils.IsEnabled(key) then
    return
  end
  local channel = type(entry.defaultChannel) == "string" and entry.defaultChannel or "SFX"
  if entry.soundKit ~= nil then
    SoundUtils.PlaySoundKit(entry.soundKit, channel)
    return
  end
  local soundFile = entry.file
  if type(soundFile) ~= "string" or soundFile == "" then
    return
  end
  SoundUtils.Play(soundFile, channel)
end

function SoundUtils.PlayGroupJoin()
  SoundUtils.PlayKey("group_join")
end

function SoundUtils.PlayPortalAvailable()
  SoundUtils.PlayKey("portal_available")
end

function SoundUtils.PlayIncomingSummon()
  SoundUtils.PlayKey("portal_available")
end

function SoundUtils.PlayBattleRes()
  SoundUtils.PlayKey("battle_res")
end

function SoundUtils.PlayBloodlust()
  SoundUtils.PlayKey("bloodlust")
end
