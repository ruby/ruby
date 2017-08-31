long_lived = []

if RUBY_VERSION > "2.2.0"
  3.times{ GC.start(full_mark: false, immediate_mark: true, immediate_sweep: true) }
elsif
  GC.start
end

i = 0
short_lived = ''
while i<30_000_000 # while loop 1
  long_lived[0] = short_lived # write barrier
  i+=1
end
