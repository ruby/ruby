require 'thread'
# many producers, one consumer
n = 1_000_000
m = 10
q = Thread::SizedQueue.new(100)
consumer = Thread.new do
  while q.pop
    # consuming
  end
end

producers = m.times.map do
  Thread.new do
    while n > 0
      q.push true
      n -= 1
    end
  end
end
producers.each(&:join)
q.push nil
consumer.join
