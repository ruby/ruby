require 'thread'
# on producer, one consumer

n = 1_000_000
q = Thread::SizedQueue.new(100)
consumer = Thread.new{
  while q.pop
    # consuming
  end
}

producer = Thread.new{
  while n > 0
    q.push true
    n -= 1
  end
  q.push nil
}

consumer.join
