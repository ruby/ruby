class C
  attr_accessor :foo
end
long_lived = C.new
GC.start
GC.start

i = 0
short_lived = ''
while i<30_000_000 # while loop 1
  long_lived.foo = short_lived # write barrier
  i+=1
end
