require 'mkmf'
$CFLAGS="-I/usr/include/ncurses -I/usr/local/include/ncurses"
$LDFLAGS="-L/usr/local/lib"
make=FALSE

have_library("mytinfo", "tgetent") if /bow/ =~ PLATFORM
if have_header("ncurses.h") and have_library("ncurses", "initscr")
  make=TRUE
elsif have_header("ncurses/curses.h") and have_library("ncurses", "initscr")
  make=TRUE
elsif have_header("curses_colr/curses.h") and have_library("cur_colr", "initscr")
  make=TRUE
else
  $CFLAGS=nil
  have_library("termcap", "tgetent") 
  if have_library("curses", "initscr")
    make=TRUE
  end
end

if make then
  for f in %w(isendwin ungetch beep doupdate flash deleteln wdeleteln)
    have_func(f)
  end
  create_makefile("curses")
end
