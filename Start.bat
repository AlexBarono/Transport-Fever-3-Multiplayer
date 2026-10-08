@echo off
rem Startet die Oberflaeche zum Einrichten des Multiplayer-Tests (Doppelklick).
rem v34: PowerShell startet versteckt, es bleibt kein schwarzes Fenster offen. Fehler zeigt der Launcher selbst an.
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0launcher\launcher.ps1"
