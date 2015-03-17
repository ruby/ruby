long_lived = []

if RUBY_VERSION > "2.2.0"
  3.times{ GC.start(immediate_mark: false, lazy_sweep: false) }
elsif
  GC.start
end

i = 0
short_lived = ''
while i<30_000_000 # while loop 1
  long_lived[0] = short_lived # write barrier
  i+=1
end
