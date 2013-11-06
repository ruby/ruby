require 'thread'

n = 1_000_000
q = Queue.new
consumer = Thread.new{
  while q.pop
    # consuming
  end
}

producer = Thread.new{
  n.times{
    q.push true
  }
  q.push nil
}

consumer.join
