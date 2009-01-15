require 'mkmf'

dir_config('curses')
dir_config('ncurses')
dir_config('termcap')

make=false
headers = []
have_library("mytinfo", "tgetent") if /bow/ =~ RUBY_PLATFORM
have_library("tinfo", "tgetent") or have_library("termcap", "tgetent")
if have_header(*curses=%w"ncurses.h") and (have_library("ncursesw", "initscr") or have_library("ncurses", "initscr"))
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
    have_func(f) || (have_macro(f, curses) && $defs.push(format("-DHAVE_%s", f.upcase)))
  end
  flag = "-D_XOPEN_SOURCE_EXTENDED"
  if try_static_assert("sizeof(char*)>sizeof(int)", %w[stdio.h stdlib.h]+curses , flag)
    $defs << flag
  end
  create_makefile("curses")
end
