require "mkmf"

have_library("termcap", "tgetnum")
if have_header("readline/readline.h") and
    have_header("readline/history.h") and
    have_library("readline", "readline")
  create_makefile("readline")
end
