@echo off
chcp 65001 >nul 2>&1
setlocal
cd /d "%~dp0"
title ohc VS Code offline kit
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
echo.
pause
