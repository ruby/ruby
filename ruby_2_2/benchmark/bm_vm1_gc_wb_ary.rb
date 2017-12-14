long_lived = []
GC.start
GC.start

i = 0
short_lived = ''
while i<30_000_000 # while loop 1
  long_lived[0] = short_lived # write barrier
  i+=1
end
