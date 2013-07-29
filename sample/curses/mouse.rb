require "curses"

def show_message(*msgs)
  message = msgs.join
  width = message.length + 6
  win = Curses::Window.new(5, width,
                           (Curses.lines - 5) / 2, (Curses.cols - width) / 2)
  win.keypad = true
  win.attron(Curses.color_pair(Curses::COLOR_RED)){
    win.box(?|, ?-, ?+)
  }
  win.setpos(2, 3)
  win.addstr(message)
  win.refresh
  win.getch
  win.close
end

Curses.init_screen
Curses.start_color
Curses.init_pair(Curses::COLOR_BLUE, Curses::COLOR_BLUE, Curses::COLOR_WHITE)
Curses.init_pair(Curses::COLOR_RED, Curses::COLOR_RED, Curses::COLOR_WHITE)
Curses.crmode
Curses.noecho
Curses.stdscr.keypad(true)

begin
  Curses.mousemask(
    Curses::BUTTON1_CLICKED|Curses::BUTTON2_CLICKED|Curses::BUTTON3_CLICKED|Curses::BUTTON4_CLICKED
  )
  Curses.setpos((Curses.lines - 5) / 2, (Curses.cols - 10) / 2)
  Curses.attron(Curses.color_pair(Curses::COLOR_BLUE)|Curses::A_BOLD){
    Curses.addstr("click")
  }
  Curses.refresh
  while( true )
    c = Curses.getch
    case c
    when Curses::KEY_MOUSE
      m = Curses::getmouse
      if( m )
	show_message("getch = #{c.inspect}, ",
		     "mouse event = #{'0x%x' % m.bstate}, ",
		     "axis = (#{m.x},#{m.y},#{m.z})")
      end
      break
    end
  end
  Curses.refresh
ensure
  Curses.close_screen
end
