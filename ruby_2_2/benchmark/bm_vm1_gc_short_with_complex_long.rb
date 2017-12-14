def nested_hash h, n
  if n == 0
    ''
  else
    10.times{
      h[Object.new] = nested_hash(h, n-1)
    }
  end
end

long_lived = Hash.new
nested_hash long_lived, 6

GC.start
GC.start

i = 0
while i<30_000_000 # while loop 1
  a = '' # short-lived String
  b = ''
  c = ''
  d = ''
  e = ''
  f = ''
  i+=1
end

