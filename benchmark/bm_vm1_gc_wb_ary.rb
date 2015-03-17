short_lived_ary = []

i = 0
short_lived = ''
while i<30_000_000 # while loop 1
  short_lived_ary[0] = short_lived # write barrier
  i+=1
end
