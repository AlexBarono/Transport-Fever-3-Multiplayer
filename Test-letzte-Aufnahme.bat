@echo off
rem Wiederholt die gesicherte Bauaufnahme, ohne die Aktionen neu aufnehmen zu muessen.
rem v34: PowerShell startet versteckt, es bleibt kein schwarzes Fenster offen. Fehler zeigt der Launcher selbst an.
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0launcher\launcher.ps1" -ReplayLog "%~dp0tests\fixtures\run29-replay.log"
