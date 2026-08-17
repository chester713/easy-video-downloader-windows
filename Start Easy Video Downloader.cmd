@echo off
title Easy Video Downloader
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0EasyVideoDownloader.ps1"
if errorlevel 1 (
  echo.
  echo The app stopped because of an unexpected error.
  pause
)
