require "mkmf"

dir_config("readline")
have_library("user32", nil) if /cygwin/ === RUBY_PLATFORM
have_library("termcap", "tgetnum") or
  have_library("curses", "tgetnum") or
  have_library("ncurses", "tgetnum")
if have_header("readline/readline.h") and
    have_header("readline/history.h") and
    have_library("readline", "readline")
  create_makefile("readline")
end
