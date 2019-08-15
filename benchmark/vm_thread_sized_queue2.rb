require 'thread'
# one producer, many consumers
n = 1_000_000
m = 10
q = Thread::SizedQueue.new(100)
consumers = m.times.map do
  Thread.new do
    while q.pop
      # consuming
    end
  end
end

producer = Thread.new do
  while n > 0
    q.push true
    n -= 1
  end
  m.times { q.push nil }
end

producer.join
consumers.each(&:join)
