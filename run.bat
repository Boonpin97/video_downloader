@echo off
rem Launches the already-built Video Downloader. Compiles nothing.
rem Build once with:  flutter build windows --release
setlocal

rem %~dp0 is this script's own folder, so the shortcut works from anywhere.
set "ROOT=%~dp0"
set "EXE=%ROOT%build\windows\x64\runner\Release\video_downloader.exe"

rem Fall back to a debug build if no release build exists.
if not exist "%EXE%" set "EXE=%ROOT%build\windows\x64\runner\Debug\video_downloader.exe"

if not exist "%EXE%" (
    echo.
    echo   Video Downloader has not been built yet.
    echo.
    echo   Build it once from this folder with:
    echo.
    echo       flutter build windows --release
    echo.
    pause
    exit /b 1
)

rem The empty "" is the window title start expects; without it, start would
rem treat the quoted exe path as the title and never launch anything.
start "" "%EXE%"
exit /b 0
