require 'mkmf'

dir_config('curses')
dir_config('ncurses')
dir_config('termcap')

make=false
have_library("mytinfo", "tgetent") if /bow/ =~ RUBY_PLATFORM
have_library("tinfo", "tgetent") or have_library("termcap", "tgetent")
if have_header(*curses=%w"ncurses.h") and have_library("ncurses", "initscr")
  make=true
elsif have_header(*curses=%w"ncurses/curses.h") and have_library("ncurses", "initscr")
  make=true
elsif have_header(*curses=%w"curses_colr/curses.h") and have_library("cur_colr", "initscr")
  curses.unshift("varargs.h")
  make=true
elsif have_header(*curses=%w"curses.h") and have_library("curses", "initscr")
  make=true
end

if make
  for f in %w(beep bkgd bkgdset curs_set deleteln doupdate flash getbkgd getnstr init isendwin keyname keypad resizeterm scrl set setscrreg ungetch wattroff wattron wattrset wbkgd wbkgdset wdeleteln wgetnstr wresize wscrl wsetscrreg def_prog_mode reset_prog_mode timeout wtimeout nodelay init_color wcolor_set)
    have_func(f)
  end
  flag = "-D_XOPEN_SOURCE_EXTENDED"
  src = "int test_var[(sizeof(char*)>sizeof(int))*2-1];"
  if try_compile(cpp_include(%w[stdio.h stdlib.h]+curses)+src , flag)
    $defs << flag
  end
  create_makefile("curses")
end
