# Dokumentation

Für Installation, gemeinsamen Start, Paketbau und Tests gilt die [Projekt-README](../README.md). Aktuell ist **Probe v70 / DLL v16**. Ältere Dokumente halten den damaligen Stand fest; Bedienung und offene Punkte können inzwischen überholt sein.

## Aktuelle Planung

Die [Roadmap ab v70](roadmap.md), Stand 23. Oktober 2026, nennt die nächsten Schritte, offene Gegentests und überprüfbare Abschlusskriterien. Der [alte Forschungsplan](plan.md) dokumentiert weiterhin den historischen Stand.

## Betrieb und Diagnose

| Thema | Einstieg |
| --- | --- |
| Zugersatz, Kaufkosten und tatsächlich angefordertes Spieltempo | [v70](v70-fahrzeugkosten-tempo.md) |
| Aufgezeichnete Straßenfehler, Tempoauswahl und längere Testfolgen | [v69](v69-tempo-stabilitaet.md) |
| Fenstergröße, neue Oberfläche, Anleitung und Freundeliste | [v68](v68-launcher-freunde.md) |
| Launcher aktualisieren, ZIP-Import und GitHub-Releases | [v66](v66-launcher-updates.md) |
| 4×-Auswahl, dauerhafte IPv6, beständige Einladungen und Straßenersatz | [v65](v65-tempo-ipv6-einladung.md) |
| Automatischer Internetstart und temporäre IPv6 | [v64](v64-internetstart.md) |
| Tempoänderungen, Geld und tatsächlicher Zeitfortschritt | [v63](v63-tempo-geld.md) |
| Straßenhaltestellen und Linienzuordnung | [v61](v61-strassenhaltestellen.md) |
| Mitspielerprotokolle beim Gastgeber | [v60](v60-mitspieler-protokolle.md) |
| Wartende Aktionen und sichere Übergabe | [v59](v59-warteschlange.md) |
| Launcher, Spielstandauswahl und automatischer Start | [v53](v53-launcher-start.md) |
| Internetverbindung und Subventionen | [v52](v52-verbindung-subventionen.md), [Internetarchitektur ab v49](v49-internet.md) |
| Spielstandübertragung und Messprotokolle | [Übertragungsverfahren](savegame-transfer.md), [Erweiterungen ab v48](v48-menu-transfer.md) |
| Testlabor und Aussagekraft simulierter Tests | [Testlabor-Auswertung](testlabor-auswertung.md) |

Die Dokumente enthalten Befunde, Grenzen und gezielte Prüfpläne. Ein automatischer Test ersetzt die darin genannten echten Zwei-PC-Gegentests nicht.

## Versionsbefunde

Der [Versionsverlauf bis v61](versionsverlauf.md) bewahrt die früheren Änderungsblöcke der Projekt-README. Die ausführlichen Untersuchungen bleiben separat verfügbar:

| Version | Untersuchung |
| --- | --- |
| v69 | [Tempo und Stabilität](v69-tempo-stabilitaet.md) |
| v68 | [Launcher und Freunde](v68-launcher-freunde.md) |
| v66 | [Updates im Launcher](v66-launcher-updates.md) |
| v65 | [Tempo, IPv6 und beständige Einladungen](v65-tempo-ipv6-einladung.md) |
| v64 | [Automatischer Internetstart](v64-internetstart.md) |
| v63 | [Tempo und Geld](v63-tempo-geld.md) |
| v62 | [Gemeinsame Geschwindigkeit](v62-geschwindigkeit.md) |
| v61 | [Straßenhaltestellen und Linienfehler](v61-strassenhaltestellen.md) |
| v60 | [Protokolle des Mitspielers](v60-mitspieler-protokolle.md) |
| v59 | [Wartende Aktionen](v59-warteschlange.md) |
| v58 | [Brücken, Tunnel und Bahnhofanschlüsse](v58-bruecken-anschluesse.md) |
| v57 | [Fehler im echten v56-Lauf](v57-sitzung-fehler.md) |
| v56 | [Fahrzeugkäufe und Linienzuweisung](v56-fahrzeuge.md) |
| v55 | [Baufehler, Wirtschaft und Weltvergleich](v55-bau-wirtschaft-vergleich.md) |
| v54 | [Pause nach Neuabgleich und Fahrzeugbefehle](v54-pause-fahrzeuge.md) |
| v53 | [Launcher und gemeinsamer Start](v53-launcher-start.md) |
| v52 | [Internetübertragung und Subventionen](v52-verbindung-subventionen.md) |
| v51 | [Automatischer Beitritt](v51-launcher.md) |
| v50 | [Verbindung und Ladebereitschaft](v50-verbindung.md) |
| v49 | [Internet ohne VPN](v49-internet.md) |
| v48 | [Menüpause und Spielstandübertragung](v48-menu-transfer.md) |
| v47 | [Weiterlaufen trotz Weltabweichung](v47-pause-release.md) |
| v46 | [Subventionen und Unternehmensname](v46-economy.md) |
| v45 | [Linienzuweisung](v45-line-assignment.md) |
| v44 | [Fehler beim Betreten einer Welt](v44-world-entry-fix.md) |
| v41/v42 | [Bahnhof über Forstfläche](v41-crash-auswertung.md) |
| v40 | [Depotanschluss im VPN-Test](v40-vpn-auswertung.md) |
| v39 | [VPN-Test und Kalendergeschwindigkeit](v39-vpn-auswertung.md) |
| v37 | [Übernahme und Gegenprüfung](v37-gegenpruefung.md) |

## Historische Forschung und Architektur

- [Ursprünglicher Machbarkeits- und Umsetzungsplan](plan.md)
- [Probe-Mod und erste API-Erkundung](probe-mod.md), [Ergebnisse der Phase 0](phase0-findings.md)
- [Nativer Einstiegspunkt](native-entry-point.md), [Lua-/DLL-Brücke](phase1-bridge.md)
- [Zusätzliche Aktionen](phase2-actions.md), [frühe Synchronisierung](phase3-sync.md)
- [Zuverlässiger Transport bis v30](phase4-reliable-transport.md), [Sitzung und Weltvergleich ab v31](phase5-session-world.md)
- [Frühere Fehler und Lösungen](fehler-und-loesungen.md)
- [Referenzanalyse des TF2-Multiplayer-Mods](tf2mp-reference.md)
- [Gesicherte TF3-API-Definitionen](tf3-api/tealdef/)
- [Ablage und Git-Archiv alter Testprotokolle](../logs/README.md)

Quellcode und Prüfungen stehen unter [mods](../mods/), [launcher](../launcher/), [native](../native/) und [tests](../tests/).
