# require "complex"
require "mandel"
require "tkclass"

DefaultMaxDepth = 30
DefaultSX = -2.25
DefaultSY = 1.75
DefaultEX = 1.25
DefaultEY = -1.75

def reset
  $max_depth = DefaultMaxDepth
  $s_re = DefaultSX
  $s_im = DefaultSY
  $e_re = DefaultEX
  $e_im = DefaultEY
  $dx = ($e_re - $s_re).abs / Width
  $dy = ($e_im - $s_im).abs / Height
  $photo.blank
end


Width = 400
Height = 400

$c = Canvas.new {
       width Width
       height Height
     }
$c.pack

$c_rect = Rectangle.new($c, 0, 0, Width+1, Height+1)
$c_rect.fill "white"

$colors = []

def colors_init
  $colors = []
  for i in 0 .. 125
    $colors.push(format("#%02x%02x%02x", 250 - (i*2), i*2, 0))
  end
  for i in 0 .. 125
    $colors.push(format("#%02x%02x%02x", 0, 250 - (i*2), i*2)) 
  end
  $color_max = $colors.size - 1
end

def zoom(a, b, c, d)
  center_x = (a + c) / 2
  center_y = (b + d) / 2
  size = (c - a).abs
  size = (d - b).abs if (size < (d - b).abs)
  size = 1 if (size < 1)
  zoom_rate = ((Width + Height) / 2).to_f / size
  $max_depth = ($max_depth.to_f * Math.sqrt(Math.sqrt(Math.sqrt(zoom_rate)))).to_i

  move_x_rate = (center_x - (Width / 2)).to_f / (Width / 2)
  move_y_rate = (center_y - (Height / 2)).to_f / (Height / 2)

  center_re = ($s_re + $e_re) / 2
  center_im = ($s_im + $e_im) / 2
  c_size_re = ($e_re - $s_re).abs
  c_size_im = ($e_im - $s_im).abs

  center_re = center_re + (move_x_rate * (c_size_re / 2))
  center_im = center_im - (move_y_rate * (c_size_im / 2))

  $s_re = center_re - ((c_size_re / 2) / zoom_rate)
  $s_im = center_im + ((c_size_im / 2) / zoom_rate)
  $e_re = center_re + ((c_size_re / 2) / zoom_rate)
  $e_im = center_im - ((c_size_im / 2) / zoom_rate)

  $dx = ($e_re - $s_re).abs / Width
  $dy = ($e_im - $s_im).abs / Height
  p [$s_re, $dx, $s_im, $dy]
end


def mandel(x, y)
  re = $s_re + ($dx * x)
  im = $s_im - ($dy * y)
#   z = c = Complex(re, im)
#   for i in 0 .. $max_depth
#     z = (z * z) + c
#     break if z.abs > 2
#   end
#   return i
  return Mandel.mandel(re, im, $max_depth)
end

$buf = "{"+"        "*Width+"}"
def calc
  $c.update
  return if $current_rect
  depth = 0

  for x in 0 .. Width - 1
    depth = mandel(x, $calc_y)
    if depth >= $max_depth
      $buf[x*8+1,7] = "#000000"
    else
      $buf[x*8+1,7] = $colors[$color_max * depth / $max_depth]
    end
  end
  $photo.put($buf, 0, $calc_y)

  $calc_y += 1
  if (($calc_y % 20) == 0)
    print "#{($calc_y * 100 / Height)}% done. -- depth #{$max_depth}\n"
#    $mandel.image $photo
  end

  if ($calc_y > Height - 1)
    $calc_y = StartCalcY
    $calc_on = false
#    exit
  end

  if $calc_on
    Tk.after(1) { calc() }
  end
end

$photo = TkPhotoImage.new({'width'=>Width, 'height'=>Height})
$mandel = TkcImage.new($c, Width/2, Height/2) { image $photo }
reset()
colors_init()
$calc_y = StartCalcY = 0
$calc_on = true
calc()

def clear
#  $mandel.destroy if $mandel
  $calc_y = StartCalcY
end

$start_x = $start_y = 0
$current_rect = nil

def do_press(x, y)
  $start_x = x
  $start_y = y
  $current_rect = Rectangle.new($c, x, y, x, y) { outline "white" }
end

def do_motion(x, y)
  if $current_rect
    $current_rect.coords $start_x, $start_y, x, y
  end
end

def do_release(x, y)
  if $current_rect
    $current_rect.coords $start_x, $start_y, x, y
    $current_rect.destroy
    $current_rect = nil
    clear()
    $calc_on = true
    zoom($start_x, $start_y, x, y)
    calc()
  end
end

$c.bind("1", proc{|e| do_press e.x, e.y})
$c.bind("B1-Motion", proc{|x, y| do_motion x, y}, "%x %y")
$c.bind("ButtonRelease-1", proc{|x, y| do_release x, y}, "%x %y")

begin
  Tk.mainloop
ensure
#  File.delete("#tmpmandel#.gif")
end
