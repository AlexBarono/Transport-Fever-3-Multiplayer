# Transport Fever 3 Multiplayer-Mod: Machbarkeit und Umsetzungsplan

Stand: 6. Oktober 2026 (eine Woche nach Release)

## 1. Kurzfazit

**Machbar, aber nur auf PC und nur mit einer nativen Komponente (DLL/Shared Library), nicht als reiner Lua-Mod.** Es ist ein großes Projekt (realistisch mehrere Monate Freizeitarbeit bis zu einer stabilen Alpha für 2 Spieler). Konsolen sind ausgeschlossen.

Begründung in einem Satz: TF3 hat keinen offiziellen Multiplayer, die Lua-Skripte laufen in einer Sandbox ohne Netzwerkzugriff, aber für Transport Fever 2 gibt es bereits einen funktionierenden Open-Source-Ansatz (Lockstep über Command-Hooks + Lua), der sich als Vorlage eignet.

## 2. Belege

| Fakt | Quelle |
|---|---|
| TF3 erschien am 29.09.2026 (PC, Linux, macOS, PS5, Xbox), Publisher Paradox, nur Einzelspieler | [Wikipedia](https://en.wikipedia.org/wiki/Transport_Fever_3) |
| Urban Games: kein offizieller Multiplayer/Co-op, Fokus auf Einzelspieler, keine bestätigten Pläne | [transportfever3.net](https://transportfever3.net/en/guide/multiplayer-mod) (Fanseite, zitiert Entwickleraussage) |
| Noch kein Community-Multiplayer-Mod für TF3 veröffentlicht | ebd. |
| Modding: Curated Mods Program, plattformübergreifender In-Game-Mod-Hub (mod.io), Konsolen nur kuratierte Mods | [GamingOnLinux](https://www.gamingonlinux.com/2026/04/transport-fever-3-takes-modding-to-a-new-level-with-a-curated-mods-program/), [mod.io-Seite](https://mod.io/g/transportfever3/m/route-map) |
| TF3-Skriptmods: Lua, `*.gs.lua` Game Scripts mit `data()`, `api.cmd.sendCommand`, Zustand über `state:get()/set()` | [tf3-mod-template](https://github.com/maxblan/tf3-mod-template) |
| TF2-Multiplayer existiert als Community-Mod: Lockstep, Proxy-DLL (`alut.dll`), Command-Capture-Hooks, UDP-Hole-Punching-Lobby, Save-Transfer, Lua-Replikation; MIT-Lizenz; Alpha, nur mit 2 Spielern getestet, an genau einen TF2-Build gebunden | [silver2127/tpf2-multiplayer](https://github.com/silver2127/tpf2-multiplayer) |

Hinweis: Mehrere TF3-"Wikis" im Netz sind SEO-Fanseiten. Die Aussagen zur Lua-Sandbox stammen von dort und müssen am echten Spiel geprüft werden (Phase 0).

## 3. Warum ein reiner Lua-Mod nicht reicht

- Die Lua-Umgebung ist sandboxed; Netzwerk (`socket`), Dateisystem-Schreibzugriff außerhalb vorgesehener Pfade oder externe Prozesse sind sehr wahrscheinlich nicht verfügbar.
- Ohne Netzwerk können zwei Spielinstanzen nicht in Echtzeit Daten austauschen.
- Lua bleibt trotzdem wichtig: Befehle ausführen (`api.cmd.sendCommand`), Spielzustand lesen, UI und Prüfsummen.

Konsequenz: Architektur wie bei tpf2-multiplayer, also **native Komponente für Netzwerk und Hooks + Lua-Mod für Spiellogik**. Diese Mod kann nicht über den Konsolen-Mod-Hub verteilt werden und vermutlich auch nicht als kuratierter Mod, sondern nur als eigener Installer (GitHub/Nexus).

## 4. Architektur (Zielbild)

```
 Spieler A (Host)                         Spieler B
 ┌───────────────────────┐                ┌───────────────────────┐
 │ TF3                   │                │ TF3                   │
 │  ├ Lua Game Script ◄──┼─ Befehle ──────┼──► Lua Game Script     │
 │  │   (führt Befehle   │                │   (führt Befehle      │
 │  │    im selben Tick  │                │    im selben Tick     │
 │  │    aus, Checksum)  │                │    aus, Checksum)     │
 │  └ Native Hook-DLL ───┼──── UDP ───────┼── Native Hook-DLL     │
 │     (fängt Befehle ab,│  (Host = Relay)│                       │
 │      Tick-Sync, Lobby)│                │                       │
 └───────────────────────┘                └───────────────────────┘
```

- **Lockstep statt Zustandsreplikation:** Nur Spielerbefehle (Straße bauen, Linie anlegen, Fahrzeug kaufen) werden übertragen, nicht die Simulation. Jede Instanz simuliert selbst. Das ist bandbreitenarm, setzt aber voraus, dass die TF3-Simulation deterministisch ist.
- **Start:** Host schickt seinen Spielstand an alle, alle laden denselben Stand.
- **Tick-Synchronisation:** Befehle werden für einen zukünftigen Tick geplant (z. B. +N Ticks), alle Clients führen sie im selben Tick aus. Spielgeschwindigkeit/Pause wird vom Host gesteuert.
- **Desync-Erkennung:** Regelmäßig Prüfsumme über Kernzustand (Geld, Fahrzeuganzahl, Positionen) vergleichen; bei Abweichung Resync durch erneuten Save-Transfer.
- **Modi:** zuerst Co-op (eine gemeinsame Firma), später getrennte Firmen.

## 5. Umsetzungsplan

**Aktuelle Priorität (06.10.2026):** Auf Wunsch des Benutzers zuerst Bahnhöfe, Depots, Abriss, Fahrzeuge und Linien ergänzen, anschließend zwischen zwei PCs testen. Die Umsetzung in Probe v13 und die Übergabe für Claude stehen in [phase2-actions.md](phase2-actions.md). Die zusätzlichen Aktionen sind offline geprüft; ein Spielnachweis steht aus.

### Phase 0: Erkundung (2–4 Wochen)
Ziel: Klären, ob die Annahmen für TF3 gelten. Entscheidet über Go/No-Go.
1. tpf2-multiplayer komplett lesen und in TF2 ausprobieren (zeigt, welche Teile übertragbar sind).
2. TF3-Lua-Umgebung testen: Welche Globals gibt es (`io`, `os`, `socket`, `package.loadlib`)? Welche `api.*`-Funktionen? Kleiner Test-Mod, der alles auflistet.
3. Prüfen, welche Bibliotheken TF3 lädt (z. B. mit Process Monitor / `ldd` unter Linux) und ob ein Proxy-DLL-Einstieg wie bei TF2 (`alut.dll`) möglich ist.
4. **Determinismus-Test:** Denselben Spielstand zweimal laden, gleiche Befehle zum gleichen Tick ausführen, nach X Minuten Zustand vergleichen. Wenn das nicht übereinstimmt, ist Lockstep nicht möglich, und das Projekt wird deutlich schwerer (siehe Risiken).
5. Nutzungsbedingungen/EULA von TF3 und Paradox auf Reverse-Engineering-Klauseln prüfen.

**Abbruchkriterium:** kein nativer Einstiegspunkt möglich oder Simulation nicht deterministisch.

### Phase 1: Prototyp "Befehle spiegeln" (3–6 Wochen)
1. Lua-Mod, der eigene Bauaktionen als Befehlsobjekte serialisiert und aus einer Warteschlange ausführen kann.
2. Native Komponente: kleine DLL (C++), die sich lädt und eine lokale UDP-Verbindung zwischen zwei Instanzen herstellt.
3. Brücke Lua ↔ DLL finden (Hook auf die Befehlsverarbeitung, wie bei TF2, oder Datei-/Speicher-Austausch als Notlösung).
4. Erfolg: Eine Straße, die Spieler A baut, erscheint bei Spieler B (zwei Instanzen, LAN oder zwei PCs).

### Phase 2: Lockstep und Stabilität (4–8 Wochen)
1. Tick-genaue Befehlsausführung und Geschwindigkeits-/Pausensteuerung durch den Host.
2. Abdecken der wichtigsten Befehle: Straßen, Schienen, Bahnhöfe, Depots, Fahrzeuge, Linien, Abriss.
3. Prüfsummen und Desync-Erkennung, automatischer Resync per Save-Transfer.
4. Automatisierter Soak-Test (zwei Instanzen spielen stundenlang Skriptbefehle ab).

### Phase 3: Lobby und Netzwerk über das Internet (2–4 Wochen)
1. Lobby mit Host-Code, UDP-Hole-Punching, Host als Relay (Ansatz aus `netpunch/` von tpf2-multiplayer).
2. Spielstand-Übertragung an Joiner.
3. Einfache Lobby-UI im Spiel (Lua-UI) oder als Overlay.

### Phase 4: Release als Alpha (2–3 Wochen)
1. Installer für Windows (Steam-Version), danach Linux.
2. Versionsprüfung: Mod verweigert den Start, wenn der TF3-Build nicht passt (Patches brechen Hooks).
3. Veröffentlichung auf GitHub (Open Source, z. B. MIT) und Nexus; Feedback-Kanal.

### Phase 5: Ausbau
- Getrennte Firmen pro Spieler, mehr als 2 Spieler, Chat, Kompatibilität mit beliebten Mods.
- Schnelle Anpassung nach jedem TF3-Patch (Hook-Signaturen per Pattern-Scan statt fester Adressen).

## 6. Werkzeuge und Kenntnisse

- **Lua** (Game Scripts, TF2/TF3-API)
- **C++** (DLL, Hooks, z. B. MinHook), Netzwerkprogrammierung (UDP)
- **Reverse Engineering:** x64dbg, Ghidra oder IDA Free, Cheat Engine zum Finden von Datenstrukturen
- Git/GitHub, ein zweiter PC oder zwei Spielinstanzen zum Testen

Wer noch kein C++/Reverse Engineering kann: zuerst nur Phase 0 Punkt 1–2 und die Lua-Teile übernehmen und mit den Autor:innen von tpf2-multiplayer Kontakt aufnehmen.

## 7. Risiken

| Risiko | Auswirkung | Gegenmaßnahme |
|---|---|---|
| TF3-Simulation nicht deterministisch | Lockstep unmöglich, Wechsel zu Zustandsreplikation (sehr viel aufwendiger) | Phase-0-Test vor allem anderen |
| Patches ändern Spielbinary | Mod bricht nach jedem Update | Pattern-Scanning, Build-Prüfung, schnelle Updates |
| Rechtliches (EULA, Paradox) | Abmahnung/Takedown möglich | EULA prüfen, keine Spieldateien verteilen, Open Source, nicht-kommerziell |
| Urban Games liefert offiziellen Multiplayer nach | Mod wird überflüssig | Akzeptiertes Risiko; Erkenntnisse bleiben wertvoll |
| Fremde Mods verändern Befehle | Desyncs | Mod-Liste beim Join abgleichen |

## 8. Empfehlung

1. Mit Phase 0 starten und tpf2-multiplayer als Vorlage nehmen statt bei null anzufangen.
2. Ein GitHub-Repository anlegen und hier im Projekt verbinden, dann kann ich den Lua-Erkundungsmod (Phase 0, Punkt 2) und das Grundgerüst schreiben.
