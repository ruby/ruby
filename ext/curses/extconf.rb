require 'mkmf'
$CFLAGS="-I/usr/include/ncurses -I/usr/local/include/ncurses"
$LDFLAGS="-L/usr/local/lib"
make=FALSE
if have_header("ncurses.h") and have_library("ncurses", "initscr")
  make=TRUE
elsif have_header("ncurses/curses.h") and have_library("ncurses", "initscr")
  make=TRUE
else
  $CFLAGS=nil
  have_library("termcap", "tgetent") 
  if have_library("curses", "initscr")
    make=TRUE
  end
end

if make then
  for f in ["isendwin", "ungetch", "beep"]
    have_func(f)
  end
  create_makefile("curses")
end
