# many threads, one mutex, many condvars
require 'thread'
m = Thread::Mutex.new
cv1 = Thread::ConditionVariable.new
cv2 = Thread::ConditionVariable.new
max = 1000
n = 100
waiting = 0
scvs = []
waiters = n.times.map do |i|
  start_cv = Thread::ConditionVariable.new
  scvs << start_cv
  start_mtx = Thread::Mutex.new
  start_mtx.synchronize do
    th = Thread.new(start_mtx, start_cv) do |sm, scv|
      m.synchronize do
        sm.synchronize { scv.signal }
        max.times do
          cv2.signal if (waiting += 1) == n
          cv1.wait(m)
        end
      end
    end
    start_cv.wait(start_mtx)
    th
  end
end
m.synchronize do
  max.times do
    cv2.wait(m) until waiting == n
    waiting = 0
    cv1.broadcast
  end
end
waiters.each(&:join)
