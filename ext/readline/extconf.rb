require "mkmf"

dir_config("readline")
have_library("user32", nil) if /cygwin/ === PLATFORM
have_library("termcap", "tgetnum")
have_library("curses", "tgetnum")
if have_header("readline/readline.h") and
    have_header("readline/history.h") and
    have_library("readline", "readline")
  create_makefile("readline")
end
