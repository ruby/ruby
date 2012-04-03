require 'thread'

class LocalBarrier
  def initialize(n)
    @wait = Queue.new
    @done = Queue.new
    @keeper = begin_keeper(n)
  end

  def sync
    @done.push(true)
    @wait.pop
  end

  def join
    @keeper.join
  end

  private
  def begin_keeper(n)
    Thread.start do
      n.times do
        @done.pop
      end
      n.times do
        @wait.push(true)
      end
    end
  end
end

n = 10

lb = LocalBarrier.new(n)

(n - 1).times do |i|
  Thread.start do
    sleep((rand(n) + 1) / 10.0)
    print "#{i}: done\n"
    lb.sync
    print "#{i}: cont\n"
  end
end

lb.sync
print "#{n-1}: cont\n"
# lb.join # [ruby-dev:30653]

print "exit.\n"
