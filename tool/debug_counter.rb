
ARGF.each_line{|line|
  if /^\s+COUNTER\((.+)\),$/ =~ line
    puts "\"#{$1}\","
  end
}
