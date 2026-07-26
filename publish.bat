@echo off
rem Keep this file ASCII-only: "chcp 65001" in a batch file that itself
rem contains non-ASCII text makes cmd.exe misread the rest of the file.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0publish.ps1"
