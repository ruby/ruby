require "tkclass"

$c = Canvas.new
$c.pack
$start_x = start_y = 0

def do_press(x, y)
  $start_x = x
  $start_y = y
  $current_line = Line.new($c, x, y, x, y, 'fill' => 'gray')
end
def do_motion(x, y)
  if $current_line
    $current_line.coords $start_x, $start_y, x, y
  end
end

def do_release(x, y)
  if $current_line
    $current_line.coords $start_x, $start_y, x, y
    $current_line.fill 'black'
    $current_line = nil
  end
end

$c.bind("1", proc{|e| do_press e.x,e.y})
$c.bind("B1-Motion", proc{|e| do_motion e.x,e.y})
$c.bind("ButtonRelease-1", proc{|e| do_release e.x,e.y})
Tk.mainloop
