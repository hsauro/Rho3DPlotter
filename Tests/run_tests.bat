@echo off
rem Build and run the Rho3DPlot unit tests (RAD Studio 13 / BDS 37.0).
setlocal
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
cd /d "%~dp0"
if not exist dcu mkdir dcu
dcc64 -B -Q -CC -NUdcu -E. Rho3DTests.dpr || exit /b 1
"%~dp0Rho3DTests.exe"
exit /b %ERRORLEVEL%
