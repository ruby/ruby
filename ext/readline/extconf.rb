require "mkmf"

dir_config("readline")
have_library("user32", nil) if /cygwin/ === RUBY_PLATFORM
have_library("ncurses", "tgetnum") or
  have_library("termcap", "tgetnum") or
  have_library("curses", "tgetnum")

if have_header("readline/readline.h") and
    have_header("readline/history.h") and
    have_library("readline", "readline")
  if have_func("rl_filename_completion_function")
    $CFLAGS += "-DREADLINE_42_OR_LATER"
  end
  create_makefile("readline")
end
