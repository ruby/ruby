short_lived_ary = []

if RUBY_VERSION >= "2.2.0"
  GC.start(full_mark: false, immediate_mark: true, lazy_sweep: false)
end

i = 0
short_lived = ''
while i<30_000_000 # while loop 1
  short_lived_ary[0] = short_lived # write barrier
  i+=1
end
