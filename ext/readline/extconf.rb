require "mkmf"

dir_config('curses')
dir_config('ncurses')
dir_config('termcap')
dir_config("readline")
have_library("user32", nil) if /cygwin/ === RUBY_PLATFORM
have_library("ncurses", "tgetnum") or
  have_library("termcap", "tgetnum") or
  have_library("curses", "tgetnum")

if have_header("readline/readline.h") and
    have_header("readline/history.h") and
    have_library("readline", "readline")
  if have_func("rl_filename_completion_function")
    $CFLAGS += " -DREADLINE_42_OR_LATER"
  end
  if have_func("rl_cleanup_after_signal")
    $CFLAGS += " -DREADLINE_40_OR_LATER"
  end
  if try_link(<<EOF, $libs)
#include <stdio.h>
#include <readline/readline.h>
main() {rl_completion_append_character = 1;}
EOF
    # this feature is implemented in readline-2.1 or later. 
    $CFLAGS += " -DREADLINE_21_OR_LATER"
  end
  create_makefile("readline")
end
