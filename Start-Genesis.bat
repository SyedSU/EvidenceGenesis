@echo off
cd /d "%~dp0"
where py >nul 2>nul
if %errorlevel% equ 0 (
    py runtime\server.py
) else (
    python runtime\server.py
)
pause
