#!/usr/local/bin/ruby

require "curses"

if ARGV.size != 1 then
  printf("usage: view file\n");
  exit
end
begin
  fp = open(ARGV[0], "r")
rescue
  raise "cannot open file: #{ARGV[1]}"
end

# signal(SIGINT, finish)

Curses.init_screen
Curses.nonl
Curses.cbreak
Curses.noecho

$screen = Curses.stdscr

$screen.scrollok(true)
#$screen.keypad(true)

# slurp the file
$data_lines = []
fp.each_line { |l|
  $data_lines.push(l.chop)
}
fp.close

$top = 0
$data_lines[0..$screen.maxy-1].each_with_index{|line, idx|
  $screen.setpos(idx, 0)
  $screen.addstr(line)
}
$screen.setpos(0,0)
$screen.refresh

def scroll_up
  if( $top > 0 )
    $screen.scrl(-1)
    $top -= 1
    str = $data_lines[$top]
    if( str )
      $screen.setpos(0, 0)
      $screen.addstr(str)
    end
    return true
  else
    return false
  end
end

def scroll_down
  if( $top + $screen.maxy < $data_lines.length )
    $screen.scrl(1)
    $top += 1
    str = $data_lines[$top + $screen.maxy - 1]
    if( str )
      $screen.setpos($screen.maxy - 1, 0)
      $screen.addstr(str)
    end
    return true
  else
    return false
  end
end

while true
  result = true
  c = Curses.getch
  case c
  when Curses::KEY_DOWN, Curses::KEY_CTRL_N
    result = scroll_down
  when Curses::KEY_UP, Curses::KEY_CTRL_P
    result = scroll_up
  when Curses::KEY_NPAGE, ?\s  # white space
    for i in 0..($screen.maxy - 2)
      if( ! scroll_down )
	if( i == 0 )
	  result = false
	end
	break
      end
    end
  when Curses::KEY_PPAGE
    for i in 0..($screen.maxy - 2)
      if( ! scroll_up )
	if( i == 0 )
	  result = false
	end
	break
      end
    end
  when Curses::KEY_LEFT, Curses::KEY_CTRL_T
    while( scroll_up )
    end
  when Curses::KEY_RIGHT, Curses::KEY_CTRL_B
    while( scroll_down )
    end
  when ?q
    break
  else
    $screen.setpos(0,0)
    $screen.addstr("[unknown key `#{Curses.keyname(c)}'=#{c}] ")
  end
  if( !result )
    Curses.beep
  end
  $screen.setpos(0,0)
end
Curses.close_screen
