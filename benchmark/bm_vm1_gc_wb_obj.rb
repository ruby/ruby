class C
  attr_accessor :foo
end
short_lived_obj = C.new

if RUBY_VERSION >= "2.2.0"
  GC.start(full_mark: false, immediate_mark: true, lazy_sweep: false)
end

i = 0
short_lived = ''
while i<30_000_000 # while loop 1
  short_lived_obj.foo = short_lived # write barrier
  i+=1
end
