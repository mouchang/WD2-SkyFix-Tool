@echo off
chcp 65001 >nul
title Watch Dogs 2 - Sky Fix Tool
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0WD2SkyFixTool.ps1"
if errorlevel 1 (
  echo.
  echo [ERROR] Script exited abnormally. Press any key to close...
  pause >nul
)