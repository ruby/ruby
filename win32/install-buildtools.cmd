@echo off
setlocal

set components=VC.Tools.x86.x64 VC.Redist.14.Latest CoreBuildTools
set components=%components% Windows11SDK.26100
if /i "%PROCESSOR_ARCHITECTURE%" == "ARM64" (
    set components=%components% VC.Tools.ARM64 VC.Tools.ARM64EC
)
set override=--passive
for %%I in (%components%) do (
    call set override=%%override%% --add Microsoft.VisualStudio.Component.%%I
)
echo on
winget install --id Microsoft.VisualStudio.2022.BuildTools --override "%override%"
