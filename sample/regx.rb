st = "\033[7m"
en = "\033[m"
#st = "<<"
#en = ">>"

while TRUE
  print "str> "
  STDOUT.flush
  input = gets
  break if not input
  if input != ""
    str = input
    str.chop!
  end
  print "pat> "
  STDOUT.flush
  re = gets
  break if not re
  re.chop!
  str.gsub! re, "#{st}\\&#{en}"
  print str, "\n"
end
print "\n"
