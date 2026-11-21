setlocal EnableExtensions DisableDelayedExpansion
if not defined V set V=0
if not defined args (
 goto :return_arg
)
set INPUT=%args%
set OUTBUF=
set UNQ=
set QTD=

set INPUT=%INPUT:#=#35%
set INPUT=%INPUT:@=#64%
set "PENDING=%INPUT:"=@sep%" &:: escape double quotes and split consecutive marks

::#### split into unquoted part, quoted part, remains
:loop

for /F "tokens=1,2* delims=@" %%I in (" %PENDING%") do (
  set "UNQ=%%I"
  set "QTD=%%J"
  set "PENDING=%%K"
)
set "UNQ=%UNQ:~1%"

if %V%==1 (
  echo unquoted:
  (echo UNQ :"%UNQ%")&(echo QTD :"%QTD%")&(echo REST:"%PENDING%")&(if defined OUTBUF echo OUTBUF:"%OUTBUF%")
)

if defined QTD     (set "QTD=%QTD:~3%")
if defined PENDING (set "PENDING=%PENDING:~3%")

if %V%==1 (
  (echo QTD :"%QTD%")&(echo REST:"%PENDING%")
)

if not defined UNQ if defined OUTBUF (
  set concat_next=true
  goto :process_unquote
)

set concat_prev=
set concat_check=
if defined UNQ (set "concat_check=%UNQ:~0,1%")
if not "%concat_check%"==" " (set concat_prev=true)

set concat_next=
set concat_check=
if defined UNQ (set "concat_check=%UNQ:~-1%")
if not "%concat_check%"==" " (set concat_next=true)

if not defined concat_prev if defined OUTBUF (
  goto :return_arg
)

::#### process unquoted part
:process_unquote

if defined UNQ if "%UNQ: =%"=="" (set UNQ=)
if not defined UNQ goto :process_quoted

for /F "tokens=1* eol=" %%I in ("%UNQ%") do (
  set "token=%%I"
  set "UNQ=%%J"
)

if %V%==1 (
  (echo unq :"%token%")&(echo UNQ :"%UNQ%")
)

set "OUTBUF=%OUTBUF%%token%"
if defined UNQ (
  goto :return_arg
) else (
  if not defined concat_next (
    goto :return_arg
  )
)

::#### process quoted part
:process_quoted

if %V%==1 (
  echo quoted:
  (echo UNQ :"%UNQ%")&(echo QTD :"%QTD%")&(echo REST:"%PENDING%")&(if defined OUTBUF echo OUTBUF:"%OUTBUF%")
)

set "OUTBUF=%OUTBUF%%QTD%"
set QTD=

if not defined PENDING (
  goto :return_arg
)
goto :loop

::#### return splitted argv
:return_arg

set "argv=%OUTBUF%"
if defined argv (set "argv=%argv:#64=@%")
if defined argv (set "argv=%argv:#35=#%")

if defined QTD (set QTD="%QTD%")

:: special handling is required because they may contain double quotes

if defined PENDING set PENDING=%PENDING:@sep="%
set args=%UNQ%%QTD%%PENDING%
if defined args set args=%args:#64=@%
if defined args set args=%args:#35=#%

endlocal & set "argv=%argv%" & set args=%args%

exit /b
