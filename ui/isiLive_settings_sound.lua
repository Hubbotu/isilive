local _, addonTable = ...
addonTable = addonTable or {}

local SettingsSound = {}
addonTable.SettingsSound = SettingsSound

local CreateSectionHeader = addonTable.SettingsControls.CreateSectionHeader
local CreateSectionNote = addonTable.SettingsControls.CreateSectionNote
local CreateSettingsCheckbox = addonTable.SettingsControls.CreateSettingsCheckbox

local SOUND_SETTING_FALLBACKS = {
  leader_transfer = {
    labelKey = "SETTINGS_SOUND_LEAD_ENABLED",
    labelFallback = "Sound: Lead Transfer",
    settingKey = "soundLeadEnabled",
    defaultEnabled = true,
  },
  group_join = {
    labelKey = "SETTINGS_SOUND_GROUP_JOIN_ENABLED",
    labelFallback = "Sound: Full Group",
    settingKey = "soundGroupJoinEnabled",
    defaultEnabled = true,
  },
  portal_available = {
    labelKey = "SETTINGS_SOUND_PORTAL_AVAILABLE",
    labelFallback = "Sound: Incoming Summon",
    settingKey = "soundPortalAvailableEnabled",
    defaultEnabled = true,
  },
  battle_res = {
    labelKey = "SETTINGS_SOUND_BATTLE_RES",
    labelFallback = "Sound: Battle Res",
    settingKey = "soundBattleResEnabled",
    defaultEnabled = true,
  },
  bloodlust = {
    labelKey = "SETTINGS_SOUND_BLOODLUST",
    labelFallback = "Sound: Bloodlust",
    settingKey = "soundBloodlustEnabled",
    defaultEnabled = true,
  },
}

function SettingsSound.GetSoundSettingEntries()
  local soundUtils = addonTable.SoundUtils
  local registry = type(soundUtils) == "table" and type(soundUtils.Registry) == "table" and soundUtils.Registry or nil
  local order = type(soundUtils) == "table" and type(soundUtils.SettingsOrder) == "table" and soundUtils.SettingsOrder
    or { "leader_transfer", "group_join", "portal_available", "battle_res", "bloodlust" }
  local entries = {}

  for _, key in ipairs(order) do
    local entry = registry and registry[key] or nil
    local fallback = SOUND_SETTING_FALLBACKS[key] or {}
    entries[#entries + 1] = {
      key = key,
      labelKey = type(entry) == "table" and entry.labelKey or fallback.labelKey,
      labelFallback = type(entry) == "table" and entry.labelFallback or fallback.labelFallback,
      settingKey = type(entry) == "table" and entry.settingKey or fallback.settingKey,
      defaultEnabled = type(entry) == "table" and entry.defaultEnabled or fallback.defaultEnabled,
    }
  end

  return entries
end

local function SetLocalizedText(region, key, fallback, labels)
  if region and key then
    region:SetText(labels[key] or fallback or key)
  end
end

function SettingsSound.BuildSoundSection(canvas, yOffset, labels, config, controls)
  controls.soundHeader, yOffset = CreateSectionHeader(canvas, yOffset, labels.SETTINGS_SECTION_SOUNDS or "Sounds")
  if controls.soundHeader then
    controls.soundHeader._sectionKey = "SETTINGS_SECTION_SOUNDS"
  end

  controls.soundHint, yOffset =
    CreateSectionNote(canvas, yOffset, labels.SETTINGS_SECTION_SOUNDS_HINT or "Toggle the built-in audio cues.")
  if controls.soundHint then
    controls.soundHint._sectionKey = "SETTINGS_SECTION_SOUNDS"
  end

  controls.soundChecks = controls.soundChecks or {}

  for _, entry in ipairs(SettingsSound.GetSoundSettingEntries()) do
    local checkbox, nextY = CreateSettingsCheckbox(
      canvas,
      yOffset,
      labels[entry.labelKey] or entry.labelFallback or entry.labelKey or entry.key or "Sound",
      function()
        local db = config.getDB()
        local settingKey = entry.settingKey
        if type(settingKey) == "string" and settingKey ~= "" then
          local stored = db[settingKey]
          if stored ~= nil then
            return stored == true
          end
        end
        return entry.defaultEnabled ~= false
      end,
      function(checked)
        local db = config.getDB()
        local settingKey = entry.settingKey
        if type(settingKey) == "string" and settingKey ~= "" then
          db[settingKey] = checked
        end
      end,
      entry.labelKey
    )

    if checkbox and checkbox.check then
      checkbox.check._sectionKey = "SETTINGS_SECTION_SOUNDS"
      checkbox.check._soundKey = entry.key
    end
    controls.soundChecks[entry.key] = checkbox
    yOffset = nextY
  end

  return yOffset
end

function SettingsSound.BuildVIPGuestSection(canvas, yOffset, labels, config, controls)
  controls.vipGuestHeader, yOffset =
    CreateSectionHeader(canvas, yOffset, labels.SETTINGS_SECTION_VIP_GUESTS or "VIP Guest Settings")
  if controls.vipGuestHeader then
    controls.vipGuestHeader._sectionKey = "SETTINGS_SECTION_VIP_GUESTS"
  end

  controls.vipGuestHint, yOffset = CreateSectionNote(
    canvas,
    yOffset,
    labels.SETTINGS_SECTION_VIP_GUESTS_HINT or "Special sound controls for selected guests."
  )
  if controls.vipGuestHint then
    controls.vipGuestHint._sectionKey = "SETTINGS_SECTION_VIP_GUESTS"
  end

  local function CreateVIPMountSoundCheckbox(controlKey, labelKey, fallbackLabel, dbKey, applyFnName)
    controls[controlKey], yOffset = CreateSettingsCheckbox(
      canvas,
      yOffset,
      labels[labelKey] or fallbackLabel,
      function()
        local db = config.getDB()
        return db[dbKey] == true
      end,
      function(checked)
        local db = config.getDB()
        db[dbKey] = checked == true
        local soundUtils = addonTable.SoundUtils
        if type(soundUtils) == "table" and type(soundUtils[applyFnName]) == "function" then
          soundUtils[applyFnName](checked)
        end
      end,
      labelKey
    )
    if controls[controlKey] and controls[controlKey].check then
      controls[controlKey].check._sectionKey = "SETTINGS_SECTION_VIP_GUESTS"
    end
  end

  CreateVIPMountSoundCheckbox(
    "vipAstralAurochsSound",
    "SETTINGS_VIP_ASTRAL_AUROCHS_SOUND",
    "Mute Astral Aurochs mount sound",
    "vipAstralAurochsSoundMuted",
    "ApplyAstralAurochsSoundSetting"
  )
  if controls.vipAstralAurochsSound and controls.vipAstralAurochsSound.check then
    controls.vipAstralAurochsSound.check._sectionKey = "SETTINGS_SECTION_VIP_GUESTS"
  end
  CreateVIPMountSoundCheckbox(
    "vipGrandExpeditionYakSound",
    "SETTINGS_VIP_GRAND_EXPEDITION_YAK_SOUND",
    "Mute Grand Expedition Yak mount sound",
    "vipGrandExpeditionYakSoundMuted",
    "ApplyGrandExpeditionYakSoundSetting"
  )
  CreateVIPMountSoundCheckbox(
    "vipGildedBrutosaurSound",
    "SETTINGS_VIP_GILDED_BRUTOSAUR_SOUND",
    "Mute Trader Brutosaur mount sound",
    "vipGildedBrutosaurSoundMuted",
    "ApplyGildedBrutosaurSoundSetting"
  )

  return yOffset
end

function SettingsSound.RefreshSoundControls(controls, labels, db)
  SetLocalizedText(controls.soundHeader, "SETTINGS_SECTION_SOUNDS", "Sounds", labels)
  SetLocalizedText(controls.soundHint, "SETTINGS_SECTION_SOUNDS_HINT", "Toggle the built-in audio cues.", labels)

  if controls.soundChecks then
    for _, entry in ipairs(SettingsSound.GetSoundSettingEntries()) do
      local soundControl = controls.soundChecks[entry.key]
      if soundControl then
        local fallback = SOUND_SETTING_FALLBACKS[entry.key] or {}
        soundControl.label:SetText(
          labels[entry.labelKey]
            or fallback.labelFallback
            or fallback.labelKey
            or entry.labelKey
            or entry.key
            or "Sound"
        )
      end
    end
  end

  if controls.soundChecks then
    for _, entry in ipairs(SettingsSound.GetSoundSettingEntries()) do
      local soundControl = controls.soundChecks[entry.key]
      if soundControl then
        local settingKey = entry.settingKey
        local defaultEnabled = entry.defaultEnabled ~= false
        local nextValue = defaultEnabled
        if type(settingKey) == "string" and settingKey ~= "" and db[settingKey] ~= nil then
          nextValue = db[settingKey] == true
        end
        soundControl.check:SetChecked(nextValue)
      end
    end
  end
end

function SettingsSound.RefreshVIPGuestControls(controls, labels, db)
  SetLocalizedText(controls.vipGuestHeader, "SETTINGS_SECTION_VIP_GUESTS", "VIP Guest Settings", labels)
  SetLocalizedText(
    controls.vipGuestHint,
    "SETTINGS_SECTION_VIP_GUESTS_HINT",
    "Special sound controls for selected guests.",
    labels
  )
  if controls.vipAstralAurochsSound and controls.vipAstralAurochsSound.label then
    controls.vipAstralAurochsSound.label:SetText(
      labels.SETTINGS_VIP_ASTRAL_AUROCHS_SOUND or "Mute Astral Aurochs mount sound"
    )
    controls.vipAstralAurochsSound.check:SetChecked(db.vipAstralAurochsSoundMuted == true)
  end
  if controls.vipGrandExpeditionYakSound and controls.vipGrandExpeditionYakSound.label then
    controls.vipGrandExpeditionYakSound.label:SetText(
      labels.SETTINGS_VIP_GRAND_EXPEDITION_YAK_SOUND or "Mute Grand Expedition Yak mount sound"
    )
    controls.vipGrandExpeditionYakSound.check:SetChecked(db.vipGrandExpeditionYakSoundMuted == true)
  end
  if controls.vipGildedBrutosaurSound and controls.vipGildedBrutosaurSound.label then
    controls.vipGildedBrutosaurSound.label:SetText(
      labels.SETTINGS_VIP_GILDED_BRUTOSAUR_SOUND or "Mute Trader Brutosaur mount sound"
    )
    controls.vipGildedBrutosaurSound.check:SetChecked(db.vipGildedBrutosaurSoundMuted == true)
  end
end
