require 'mkmf'

if( ! $CPPFLAGS )
  $CPPFLAGS = ""
end

make=false
have_library("mytinfo", "tgetent") if /bow/ =~ RUBY_PLATFORM
if have_header("ncurses.h") and have_library("ncurses", "initscr")
  make=true
elsif have_header("ncurses/curses.h") and have_library("ncurses", "initscr")
  make=true
elsif have_header("curses_colr/curses.h") and have_library("cur_colr", "initscr")
  make=true
else
  have_library("termcap", "tgetent") 
  if have_library("curses", "initscr")
    make=true
  end
end

if make
  for f in %w(isendwin ungetch beep getnstr wgetnstr doupdate flash deleteln wdeleteln keypad keyname init_color)
    have_func(f)
  end
  create_makefile("curses")
end
