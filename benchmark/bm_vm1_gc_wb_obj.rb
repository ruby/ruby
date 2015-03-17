class C
  attr_accessor :foo
end
short_lived_obj = C.new

i = 0
short_lived = ''
while i<30_000_000 # while loop 1
  short_lived_obj.foo = short_lived # write barrier
  i+=1
end
