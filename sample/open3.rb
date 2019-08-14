require 'open3'

a = Open3.popen3("nroff -man")
Thread.start do
  while line = gets
    a[0].print line
  end
  a[0].close
end
while line = a[1].gets
  print ":", line
end
