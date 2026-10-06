@echo off
rem Startet die Oberflaeche zum Einrichten des Multiplayer-Tests (Doppelklick).
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0launcher\launcher.ps1"
if errorlevel 1 pause
