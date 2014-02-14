require 'test/unit'
require 'thread'

class TestQueue < Test::Unit::TestCase
  def test_queue
    grind(5, 1000, 15, Queue)
  end

  def test_sized_queue
    grind(5, 1000, 15, SizedQueue, 1000)
  end

  def test_sized_queue_clear
    # Fill queue, then test that SizedQueue#clear wakes up all waiting threads
    sq = SizedQueue.new(2)
    2.times { sq << 1 }

    t1 = Thread.new do
      sq << 1
    end

    t2 = Thread.new do
      sq << 1
    end

    t3 = Thread.new do
      Thread.pass
      sq.clear
    end

    [t3, t2, t1].each(&:join)
    assert_equal sq.length, 2
  end

  def grind(num_threads, num_objects, num_iterations, klass, *args)
    from_workers = klass.new(*args)
    to_workers = klass.new(*args)

    workers = (1..num_threads).map {
      Thread.new {
        while object = to_workers.pop
          from_workers.push object
        end
      }
    }

    Thread.new {
      num_iterations.times {
        num_objects.times { to_workers.push 99 }
        num_objects.times { from_workers.pop }
      }
    }.join

    num_threads.times { to_workers.push nil }
    workers.each { |t| t.join }

    assert_equal 0, from_workers.size
    assert_equal 0, to_workers.size
  end
end
