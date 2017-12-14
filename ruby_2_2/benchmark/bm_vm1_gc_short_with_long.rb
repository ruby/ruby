long_lived = Array.new(1_000_000){|i| "#{i}"}
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
