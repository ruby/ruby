@echo off
@setlocal EnableExtensions DisableDelayedExpansion || exit /b -1

if "%1" == "" (set gitdir=.) else (set gitdir=%1)
set TZ=UTC
for /f "usebackq tokens=1-3" %%I in (
    `git -C "%gitdir%" log -1 --no-show-signature "--date=format-local:%%F %%T" "--format=%%H %%cd" HEAD`
) do (
    set rev=%%I
    set dt=%%J
    set tm=%%K
)
if not "%dt%" == "" (
    set /a yy=%dt:-=% / 10000
    set /a mm=%dt:-=% / 100 %% 100
    set /a dd=%dt:-=% %% 100
)
for /f "usebackq tokens=1" %%I in (
    `git -C "%gitdir%" symbolic-ref --short HEAD`
) do set branch=%%I
if not "%rev%" == "" (
  echo #define RUBY_REVISION "%rev:~,10%"
  echo #define RUBY_FULL_REVISION "%rev%"
  echo #define RUBY_BRANCH_NAME "%branch%"
  echo #define RUBY_RELEASE_DATETIME "%dt%T%tm%Z"
  echo #define RUBY_RELEASE_YEAR %yy%
  echo #define RUBY_RELEASE_MONTH %mm%
  echo #define RUBY_RELEASE_DAY %dd%
)
@endlocal
