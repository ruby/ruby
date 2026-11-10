@echo off
@setlocal EnableExtensions DisableDelayedExpansion || exit /b -1
for %%I in (%*) do if not exist "%%~I/." (mkdir "%%~I" 2> nul || if not exist "%%~I/." exit /b 1)
