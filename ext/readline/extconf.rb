require "mkmf"

readline_dir = with_config("readline-dir")
if readline_dir
  $CFLAGS = "-I#{readline_dir}/include"
  $LDFLAGS = "-L#{readline_dir}/lib"
end

readline_dir = with_config("readline-include-dir")
if readline_dir
  $CFLAGS = "-I#{readline_dir}"
end

readline_dir = with_config("readline-lib-dir")
if readline_dir
  $LDFLAGS = "-L#{readline_dir}"
end

have_library("user32", nil) if /cygwin/ === PLATFORM
have_library("termcap", "tgetnum")
have_library("curses", "tgetnum")
if have_header("readline/readline.h") and
    have_header("readline/history.h") and
    have_library("readline", "readline")
  create_makefile("readline")
end
