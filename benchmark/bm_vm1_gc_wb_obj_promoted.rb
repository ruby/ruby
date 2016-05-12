class C
  attr_accessor :foo
end
long_lived = C.new

if RUBY_VERSION >= "2.2.0"
  3.times{ GC.start(full_mark: false, immediate_mark: true, lazy_sweep: false) }
elsif
  GC.start
end

i = 0
short_lived = ''
while i<30_000_000 # while loop 1
  long_lived.foo = short_lived # write barrier
  i+=1
end
