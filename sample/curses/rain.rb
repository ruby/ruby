# rain for a curses test

require "curses"

def onsig(sig)
  Curses.close_screen
  exit sig
end

def ranf
  rand(32767).to_f / 32767
end

# main #
for i in %w[HUP INT QUIT TERM]
  if trap(i, "SIG_IGN") != 0 then  # 0 for SIG_IGN
    trap(i) {|sig| onsig(sig) }
  end
end

Curses.init_screen
Curses.nl
Curses.noecho
srand

xpos = {}
ypos = {}
r = Curses.lines - 4
c = Curses.cols - 4
for i in 0 .. 4
  xpos[i] = (c * ranf).to_i + 2
  ypos[i] = (r * ranf).to_i + 2
end

i = 0
while TRUE
  x = (c * ranf).to_i + 2
  y = (r * ranf).to_i + 2


  Curses.setpos(y, x); Curses.addstr(".")

  Curses.setpos(ypos[i], xpos[i]); Curses.addstr("o")

  i = if i == 0 then 4 else i - 1 end
  Curses.setpos(ypos[i], xpos[i]); Curses.addstr("O")

  i = if i == 0 then 4 else i - 1 end
  Curses.setpos(ypos[i] - 1, xpos[i]);      Curses.addstr("-")
  Curses.setpos(ypos[i],     xpos[i] - 1); Curses.addstr("|.|")
  Curses.setpos(ypos[i] + 1, xpos[i]);      Curses.addstr("-")

  i = if i == 0 then 4 else i - 1 end
  Curses.setpos(ypos[i] - 2, xpos[i]);       Curses.addstr("-")
  Curses.setpos(ypos[i] - 1, xpos[i] - 1);  Curses.addstr("/ \\")
  Curses.setpos(ypos[i],     xpos[i] - 2); Curses.addstr("| O |")
  Curses.setpos(ypos[i] + 1, xpos[i] - 1); Curses.addstr("\\ /")
  Curses.setpos(ypos[i] + 2, xpos[i]);       Curses.addstr("-")

  i = if i == 0 then 4 else i - 1 end
  Curses.setpos(ypos[i] - 2, xpos[i]);       Curses.addstr(" ")
  Curses.setpos(ypos[i] - 1, xpos[i] - 1);  Curses.addstr("   ")
  Curses.setpos(ypos[i],     xpos[i] - 2); Curses.addstr("     ")
  Curses.setpos(ypos[i] + 1, xpos[i] - 1);  Curses.addstr("   ")
  Curses.setpos(ypos[i] + 2, xpos[i]);       Curses.addstr(" ")


  xpos[i] = x
  ypos[i] = y
  Curses.refresh
  sleep(0.5)
end

# end of main
