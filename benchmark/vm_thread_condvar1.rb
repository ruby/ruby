# two threads, two mutex, two condvar ping-pong
require 'thread'
m1 = Thread::Mutex.new
m2 = Thread::Mutex.new
cv1 = Thread::ConditionVariable.new
cv2 = Thread::ConditionVariable.new
max = 100000
i = 0
wait = nil
m2.synchronize do
  wait = Thread.new do
    m1.synchronize do
      m2.synchronize { cv2.signal }
      while (i += 1) < max
        cv1.wait(m1)
        cv2.signal
      end
    end
  end
  cv2.wait(m2)
end
m1.synchronize do
  while i < max
    cv1.signal
    cv2.wait(m1)
  end
end
wait.join
