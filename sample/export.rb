# methos access permission
# output:
#	foobar
#	foo

class foo
  export(\printf)
end

def foobar
  print "foobar\n"
end

f = foo.new
#foo.unexport(\printf)
foo.export(\foobar)
f.foobar
f.printf "%s\n", foo
