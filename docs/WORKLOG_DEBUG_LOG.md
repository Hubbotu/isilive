# Plan: Debug-Log System

## Status: BEREIT ZUM STARTEN — eine Entscheidung noch offen (siehe unten)

---

## Offene Entscheidung (ZUERST klären!)

**Option A — RuntimeLog erweitern (Empfehlung):**
- Alles geht in den bestehenden `ctx.runtimeLogController`
- `maxEntries` 800 → 10000 (eine Zeile in `factory_frame_bridge.lua:98`)
- Kein neues Modul, keine neuen Commands
- `/isilive log on|off|clear|tail [n]` existiert bereits vollständig
- `ctx.Print`-Ausgaben landen im selben Stream → hilfreich für Kontext
- `logRuntimeTrace` und `logFn` sind in wiring/controllers bereits verdrahtet

**Option B — Neues DebugLog-Modul (saubere Trennung):**
- Neue Datei `core/isiLive_debug_log.lua`
- Eigener `IsiLiveDB.uiDebugLog` Key, eigener Toggle `IsiLiveDB.uiDebugLogEnabled`
- Neuer Command `/isilive ulog on|off|clear|tail [n]`
- RuntimeLog bleibt für Print-Output, DebugLog nur für feinkörnige Traces

**Wenn nicht anders entschieden: Option A nehmen.**

---

## Log-Format (gilt für beide Optionen)

```
HH:MM:SS.mmm [MODULE] event_name key=val key=val
```

Timestamp-Funktion:
```lua
local function GetDebugTimestamp()
  local t = GetTime and GetTime() or 0
  local h = math.floor(t / 3600) % 24
  local m = math.floor(t / 60) % 60
  local s = math.floor(t) % 60
  local ms = math.floor((t % 1) * 1000)
  return string.format("%02d:%02d:%02d.%03d", h, m, s, ms)
end
```
**Wichtig:** `GetTime()` gibt Sekunden seit Serverstart zurück, nicht Uhrzeit.
Für Uhrzeit: `date("%H:%M:%S")` + `GetTime() % 1` für ms kombinieren.
Alternativ einfach `GetTime()` als float — Einträge bleiben sortierbar/sequenzierbar.

---

## Schritt 1: Kapazität erhöhen (Option A) ODER neues Modul (Option B)

### Option A: Eine Zeile ändern
**Datei:** `factory/isiLive_factory_frame_bridge.lua`, Zeile 98
```lua
-- vorher:
ctx.runtimeLogController = modules.runtimeLog.CreateController({
  maxEntries = 800,
})
-- nachher:
ctx.runtimeLogController = modules.runtimeLog.CreateController({
  maxEntries = 10000,
})
```

### Option B: Neue Datei + TOC + Commands + Factory
(Nur wenn Option B gewählt — Detailplan dann separat ausarbeiten)

---

## Schritt 2: LFGDetect — SetLogger injizieren

**Datei:** `game/isiLive_lfg_detect.lua`

### 2a. Modul-Variable hinzufügen (nach `localeGetter`)
```lua
local debugLog = nil
```

### 2b. Setter hinzufügen (nach `LFGDetect.SetLocaleGetter`)
```lua
function LFGDetect.SetLogger(fn)
  debugLog = type(fn) == "function" and fn or nil
end

local function Log(module, event, data)
  if not debugLog then return end
  debugLog(string.format("[%s] %s %s", module, event, data or ""))
end
```

### 2c. Logging-Calls eintragen

In `OnInvited`:
```lua
Log("LFG", "invite_received", string.format("searchResultID=%s activityID=%s mapID=%s", tostring(searchResultID), tostring(info and info.activityID), tostring(mapID)))
Log("LFG", "state_set", string.format("var=pendingInvites[%s] val=%s", tostring(searchResultID), tostring(mapID)))
```

In `OnInviteAccepted`:
```lua
Log("LFG", "invite_accepted", string.format("searchResultID=%s mapID=%s", tostring(searchResultID), tostring(mapID)))
Log("LFG", "state_set", string.format("var=detectedMapID before=%s after=%s", tostring(detectedMapID), tostring(mapID)))
Log("LFG", "state_set", string.format("var=pendingAcceptedInviteMapID val=%s", tostring(mapID)))
```

In `OnInviteDeclined`:
```lua
Log("LFG", "invite_declined", string.format("searchResultID=%s mapID=%s", tostring(searchResultID), tostring(mapID)))
```

In `TriggerHighlightUpdate`:
```lua
Log("LFG", "highlight_trigger", string.format("soundContext=%s detectedMapID=%s", tostring(soundContext), tostring(detectedMapID)))
```

In `ClearDetectedState`:
```lua
Log("LFG", "clear_detected_state", string.format("path=queue_ticker lastQueueMapID=%s", tostring(lastQueueMapID)))
```

In `ClearAllStateImpl`:
```lua
Log("LFG", "clear_all_state", string.format("hadState=%s", tostring(hadState)))
```

In `CheckActiveGroup`:
```lua
-- wenn mapID gefunden:
Log("LFG", "queue_listing_detected", string.format("mapID=%s lastQueueMapID=%s", tostring(mapID), tostring(lastQueueMapID)))
Log("LFG", "state_set", string.format("var=lastQueueMapID val=%s", tostring(mapID)))
Log("LFG", "state_set", string.format("var=detectedMapID val=%s", tostring(mapID)))
-- wenn mapID nil und lastQueueMapID gesetzt:
Log("LFG", "queue_listing_cleared", "no_active_entry")
```

In GROUP_ROSTER_UPDATE handler:
```lua
Log("LFG", "group_roster_update", string.format("inGroup=%s memberCount=%s pendingAccept=%s", tostring(inGroup), tostring(groupMemberCount), tostring(pendingAcceptedInviteMapID)))
```

---

## Schritt 3: LFGDetect.SetLogger in Factory verdrahten

**Datei:** `factory/isiLive_factory_controllers.lua`, nach `lfgDetect.SetLocaleGetter` (ca. Zeile 769)

```lua
if type(lfgDetect.SetLogger) == "function" then
  -- Option A:
  lfgDetect.SetLogger(ctx.runtimeLogController and ctx.runtimeLogController.Log or nil)
  -- Option B:
  -- lfgDetect.SetLogger(ctx.debugLogController and ctx.debugLogController.Log or nil)
end
```

---

## Schritt 4: UpdateMPlusTeleportButton instrumentieren

**Datei:** `factory/isiLive_factory_controllers.lua`, Funktion `ctx.UpdateMPlusTeleportButton` (ab Zeile 728)

`logFn` aus `runtimeLogController` direkt in der Funktion holen und Calls eintragen:

```lua
ctx.UpdateMPlusTeleportButton = function(soundContext)
  local logFn = ctx.runtimeLogController and ctx.runtimeLogController.Log or nil
  if logFn then logFn(string.format("[TP] update_button_called soundContext=%s", tostring(soundContext))) end

  -- nach detectedMapID holen:
  if logFn then logFn(string.format("[TP] lfg_detected_map detectedMapID=%s", tostring(detectedMapID))) end

  -- nach resolvedSpellID aus detectedMapID:
  if logFn then logFn(string.format("[TP] spell_from_lfg mapID=%s resolvedSpellID=%s", tostring(detectedMapID), tostring(resolvedSpellID))) end

  -- nach fallback ResolveActiveTeleportSpellID:
  if logFn then logFn(string.format("[TP] spell_from_active resolvedSpellID=%s", tostring(resolvedSpellID))) end

  -- vor mainFrame show:
  if logFn then logFn(string.format("[TP] frame_show_check spellFound=%s soundContext=%s frameShown=%s", tostring(resolvedSpellID ~= nil), tostring(soundContext), tostring(ctx.mainFrame and ctx.mainFrame:IsShown()))) end

  -- vor UpdateButtons:
  if logFn then logFn(string.format("[TP] update_buttons_called resolvedSpellID=%s", tostring(resolvedSpellID))) end

  ctx.teleportUIController.UpdateButtons(resolvedSpellID, soundContext)
end
```

**Hinweis:** `logFn` in `factory_controllers.lua` existiert bereits in `BuildLFGGroupRosterTraceLogger`
(andere Closure). In `UpdateMPlusTeleportButton` lokal neu aus `ctx.runtimeLogController.Log` ziehen.

---

## Schritt 5: sendOwnKeystoneToChat instrumentieren

**Datei:** `factory/isiLive_controller_wiring.lua`

`logRuntimeTrace` ist bereits auf Zeile 512 in den Wiring-opts übergeben.
Im `sendOwnKeystoneToChat`-Closure (ca. Zeile 437ff) über `ctx.logRuntimeTrace` oder `opts.logRuntimeTrace` verfügbar.

Calls eintragen:
```lua
-- Beim Klick:
if ctx.logRuntimeTrace then ctx.logRuntimeTrace(string.format("[KEYSTONE] share_triggered isInGroup=%s", tostring(ctx.isInGroup and ctx.isInGroup()))) end

-- Nach getRoster():
if ctx.logRuntimeTrace then ctx.logRuntimeTrace(string.format("[KEYSTONE] roster_resolved memberCount=%s", tostring(roster and #roster or "nil"))) end

-- Nach getOwnedKeystoneSnapshot():
if ctx.logRuntimeTrace then ctx.logRuntimeTrace(string.format("[KEYSTONE] snapshot_resolved mapID=%s level=%s", tostring(snapshot and snapshot.mapID or "nil"), tostring(snapshot and snapshot.level or "nil"))) end

-- Bei Abbruch:
if ctx.logRuntimeTrace then ctx.logRuntimeTrace(string.format("[KEYSTONE] aborted reason=%s", reason)) end

-- Bei Erfolg:
if ctx.logRuntimeTrace then ctx.logRuntimeTrace(string.format("[KEYSTONE] chat_sent msg=%s", tostring(msg))) end
```

**WICHTIG:** Genaue Position von `sendOwnKeystoneToChat` in wiring.lua zuerst lesen, dann Calls eintragen.

---

## Schritt 6: ReadyCheck-Handler instrumentieren

**Datei:** `logic/isiLive_event_handlers_challenge.lua`

Empfängt aktuell keinen `logFn` — muss über opts injiziert werden.

### 6a. In der Factory prüfen wo der Challenge-Handler konstruiert wird:
Suchen in `factory/isiLive_factory.lua` oder `isiLive_controller_wiring.lua` nach `eventHandlersChallenge`.

### 6b. Calls in `HandleChallengeModeStart`:
```lua
log("[RC] challenge_mode_start mapID=" .. tostring(mapID))
log("[RC] state_set var=readyCheckActive val=false")
```

### 6c. Calls in READY_CHECK handler:
```lua
log("[RC] ready_check_started activeDeclineCount=" .. tostring(count))
log("[RC] reset_decline_tracking called")
```

### 6d. Calls bei Response:
```lua
log("[RC] response_received unit=" .. tostring(unit) .. " status=" .. tostring(status))
log("[RC] hold_set unit=" .. tostring(unit) .. " type=ready until=" .. tostring(until_ts))
```

**WICHTIG:** Datei zuerst vollständig lesen. Nicht raten.

---

## Schritt 7: Group/Roster-Handler instrumentieren

**Dateien:** `logic/isiLive_event_handlers.lua`, ggf. `logic/isiLive_group.lua`

Calls bei:
- GROUP_ROSTER_UPDATE empfangen
- Gruppe betreten / verlassen
- `wasInGroup`-State-Änderungen
- Roster-Snapshot erstellt

**WICHTIG:** Dateien zuerst lesen. Prüfen ob `logRuntimeTrace` bereits in den opts ist.

---

## Schritt 8: Sync/KeySync instrumentieren

**Dateien:** `logic/isiLive_sync.lua`, `logic/isiLive_keysync.lua`

`isiLive_sync.lua` ist ein Modul-Singleton (kein CreateController-Pattern).
Logging-Funktion über Setter injizieren — analog `LFGDetect.SetLogger`.

Calls bei:
- Sync-Nachricht empfangen (type, sender)
- Sync-Daten angewendet (was geändert)
- KeySync empfangen (sender, mapID, level)
- KeySync angewendet (unit)
- Cooldown-Blocker (warum nicht gesendet)

**WICHTIG:** Beide Dateien zuerst vollständig lesen. Setter-Pattern wie LFGDetect verwenden.

---

## Schritt 9: Commands (Option A: nichts nötig)

**Option A:** Fertig — `/isilive log on|off|clear|tail [n]` ist vollständig implementiert.

**Option B:** In `logic/isiLive_commands.lua`:
- `BuildDeps` um `setDebugLogEnabled`, `getDebugLogEnabled`, `clearDebugLog`, `getDebugLogCount`, `getDebugLogTail` erweitern
- `HandleULogCommand` (analog `HandleLogCommand`) hinzufügen
- `TryHandleUtilityCommands` um `"ulog"` erweitern

---

## Betroffene Dateien (Option A — keine neuen Dateien)

| Datei | Änderung |
|---|---|
| `factory/isiLive_factory_frame_bridge.lua` | maxEntries 800 → 10000 |
| `game/isiLive_lfg_detect.lua` | SetLogger + Log-Calls |
| `factory/isiLive_factory_controllers.lua` | SetLogger verdrahten + UpdateMPlusTeleportButton Calls |
| `factory/isiLive_controller_wiring.lua` | sendOwnKeystoneToChat Calls |
| `logic/isiLive_event_handlers_challenge.lua` | ReadyCheck Calls (nach Lesen) |
| `logic/isiLive_event_handlers.lua` | Roster Calls (nach Lesen) |
| `logic/isiLive_group.lua` | Group Calls (nach Lesen) |
| `logic/isiLive_sync.lua` | Sync Calls + SetLogger (nach Lesen) |
| `logic/isiLive_keysync.lua` | KeySync Calls (nach Lesen) |

---

## Implementierungsreihenfolge

1. Entscheidung: Option A oder B
2. Schritt 1: maxEntries erhöhen (eine Zeile)
3. Schritt 2+3: LFGDetect SetLogger + Factory-Verdrahtung (aktueller Bug-Bereich)
4. Schritt 4: UpdateMPlusTeleportButton (aktueller Bug-Bereich)
5. Schritt 5: sendOwnKeystoneToChat
6. Schritt 6: ReadyCheck (erst Datei lesen)
7. Schritt 7: Group/Roster (erst Dateien lesen)
8. Schritt 8: Sync/KeySync (erst Dateien lesen)
9. Ingame testen: `/isilive log on` → LFG-Einladung annehmen → `/isilive log tail 50`

---

## Kontext für spätere Session

**Aktueller offener Bug:** Terasse der Magister wird korrekt erkannt (Chat-Output ok),
aber der Teleport-Button-Highlight geht nicht.

- `UpdateMPlusTeleportButton` in `factory_controllers.lua:728` — Logging dort deckt den Bug auf
- `ACTIVITY_TO_MAP[1760] = 558` in `lfg_detect.lua` — Magisters' Terrace statisch gemappt
- `modules.teleport.ResolveTeleportSpellIDByMapID(558)` — gibt Teleport-Spell zurück (oder nil)
- Das Logging wird zeigen ob `detectedMapID=558` ankommt und ob der Spell aufgelöst wird

**Strategie:** Zuerst Schritte 2–4 implementieren (LFG + TP Logging), ingame testen,
im Log sehen wo der Pfad abbricht, dann fixen.
