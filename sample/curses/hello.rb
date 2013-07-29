require "curses"

def show_message(message)
  width = message.length + 6
  win = Curses::Window.new(5, width,
		   (Curses.lines - 5) / 2, (Curses.cols - width) / 2)
  win.box('|', '-')
  win.setpos(2, 3)
  win.addstr(message)
  win.refresh
  win.getch
  win.close
end

Curses.init_screen
begin
  Curses.crmode
# show_message("Hit any key")
  Curses.setpos((Curses.lines - 5) / 2, (Curses.cols - 10) / 2)
  Curses.addstr("Hit any key")
  Curses.refresh
  char = Curses.getch
  show_message("You typed: #{char}")
  Curses.refresh
ensure
  Curses.close_screen
end
