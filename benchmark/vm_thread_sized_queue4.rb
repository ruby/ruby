require 'thread'
# many producers, many consumers
nr = 1_000_000
n = 10
m = 10
q = Thread::SizedQueue.new(100)
consumers = n.times.map do
  Thread.new do
    while q.pop
      # consuming
    end
  end
end

producers = m.times.map do
  Thread.new do
    while nr > 0
      q.push true
      nr -= 1
    end
  end
end

producers.each(&:join)
n.times { q.push nil }
consumers.each(&:join)
