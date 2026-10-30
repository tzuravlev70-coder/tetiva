@echo off
setlocal
rem Launch TETHER. Any extra arguments are forwarded to Godot.
set "PROJECT=%~dp0"
set "GODOT=C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"

if exist "%GODOT%" (
    start "" "%GODOT%" --path "%PROJECT%." %*
    goto :eof
)

where godot >nul 2>nul
if not errorlevel 1 (
    start "" godot --path "%PROJECT%." %*
    goto :eof
)

if exist "%LOCALAPPDATA%\Programs\Godot\Godot_v4.4.1-stable_win64.exe" (
    start "" "%LOCALAPPDATA%\Programs\Godot\Godot_v4.4.1-stable_win64.exe" --path "%PROJECT%." %*
    goto :eof
)

echo Godot 4.4+ was not found.
echo Install Godot or edit the GODOT path at the top of play.bat.
pause
exit /b 1
