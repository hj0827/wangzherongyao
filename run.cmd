@echo off
setlocal
if exist "D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe" (
  set "GODOT_EXE=D:\Tools\Godot\Godot_v4.7.2-stable_win64.exe"
) else (
  set "GODOT_EXE=D:\Software\Godot\Godot_v4.7-stable_win64.exe"
)

rem 某些终端启动时 APPDATA 为空，会让 user:// 退化到工程目录（生成 godot\Godot\app_userdata）
if not defined APPDATA set "APPDATA=%USERPROFILE%\AppData\Roaming"

if not exist "%GODOT_EXE%" (
  echo [ERROR] Godot not found: %GODOT_EXE%
  echo Download Godot 4.7 stable and put it there, or edit GODOT_EXE in this file.
  exit /b 1
)

"%GODOT_EXE%" --path "%~dp0godot" %*
