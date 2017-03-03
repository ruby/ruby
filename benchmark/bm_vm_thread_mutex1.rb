# one thread, one mutex (no contention)

require 'thread'
m = Thread::Mutex.new
r = 0
max = 2000
lmax = max * max
(1..1).map{
  Thread.new{
    i = 0
    while i<lmax
      i += 1
      m.synchronize{
        r += 1
      }
    end
  }
}.each{|e|
  e.join
}
raise r.to_s if r != max * max
