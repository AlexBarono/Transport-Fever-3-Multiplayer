@echo off
rem Wiederholt die gesicherte Bauaufnahme, ohne die Aktionen neu aufnehmen zu muessen.
powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%~dp0launcher\launcher.ps1" -ReplayLog "%~dp0logs\run29-stdout.txt"
if errorlevel 1 pause
