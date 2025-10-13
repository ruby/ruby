::- Install msys packages for rubygems
::- The dependencies are taken from vcpkg.json to share the common info.

@setlocal EnableExtensions DisableDelayedExpansion || exit /b - 1
@set PROMPT=$h$e[96m$g$e[39m$s
@set script=%0
@call set "srcdir=%%script:\win32\%~nx0=%%"

@if not defined MINGW_PACKAGE_PREFIX (
    ::- Enable msys environment by ridk (from RubyInstaller-DevKit)
    where ridk >nul 2>&1 || (
        (echo MINGW_PACKAGE_PREFIX is not set, you have to enable development environment.) 1>&2
        exit /b 1
    )
    call ridk enable %*
    echo:
) else if not "%1" == "" (
    ::- Switch msys environment by ridk (from RubyInstaller-DevKit)
    call ridk enable %*
    echo:
)

@set pkgs=
@(
    for /f %%I in ('powershell -c "(ConvertFrom-Json $input).dependencies"') do @(
        call set "pkgs=%%pkgs%% %%MINGW_PACKAGE_PREFIX%%-%%%%I"
    )
) < "%srcdir%\vcpkg.json"
pacman -S --needed --noconfirm %pkgs:~1%
