require 'test/unit'
require 'thread'
require 'tmpdir'
require 'timeout'

class TestQueue < Test::Unit::TestCase
  def test_queue_initialized
    assert_raise(TypeError) {
      Queue.allocate.push(nil)
    }
  end

  def test_sized_queue_initialized
    assert_raise(TypeError) {
      SizedQueue.allocate.push(nil)
    }
  end

  def test_queue
    grind(5, 1000, 15, Queue)
  end

  def test_sized_queue
    grind(5, 1000, 15, SizedQueue, 1000)
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

  def test_sized_queue_initialize
    q = SizedQueue.new(1)
    assert_equal 1, q.max
    assert_raise(ArgumentError) { SizedQueue.new(0) }
    assert_raise(ArgumentError) { SizedQueue.new(-1) }
  end

  def test_sized_queue_assign_max
    q = SizedQueue.new(2)
    assert_equal(2, q.max)
    q.max = 1
    assert_equal(1, q.max)
    assert_raise(ArgumentError) { q.max = 0 }
    assert_equal(1, q.max)
    assert_raise(ArgumentError) { q.max = -1 }
    assert_equal(1, q.max)

    before = q.max
    q.max.times { q << 1 }
    t1 = Thread.new { q << 1 }
    sleep 0.01 until t1.stop?
    q.max = q.max + 1
    assert_equal before + 1, q.max
  ensure
    t1.join if t1
  end

  def test_queue_pop_interrupt
    q = Queue.new
    t1 = Thread.new { q.pop }
    sleep 0.01 until t1.stop?
    t1.kill.join
    assert_equal(0, q.num_waiting)
  end

  def test_queue_pop_non_block
    q = Queue.new
    assert_raise_with_message(ThreadError, /empty/) do
      q.pop(true)
    end
  end

  def test_sized_queue_pop_interrupt
    q = SizedQueue.new(1)
    t1 = Thread.new { q.pop }
    sleep 0.01 until t1.stop?
    t1.kill.join
    assert_equal(0, q.num_waiting)
  end

  def test_sized_queue_pop_non_block
    q = SizedQueue.new(1)
    assert_raise_with_message(ThreadError, /empty/) do
      q.pop(true)
    end
  end

  def test_sized_queue_push_interrupt
    q = SizedQueue.new(1)
    q.push(1)
    assert_raise_with_message(ThreadError, /full/) do
      q.push(2, true)
    end
  end

  def test_sized_queue_push_non_block
    q = SizedQueue.new(1)
    q.push(1)
    t1 = Thread.new { q.push(2) }
    sleep 0.01 until t1.stop?
    t1.kill.join
    assert_equal(0, q.num_waiting)
  end

  def test_thr_kill
    bug5343 = '[ruby-core:39634]'
    Dir.mktmpdir {|d|
      timeout = 30
      total_count = 250
      begin
        assert_normal_exit(<<-"_eom", bug5343, {:timeout => timeout, :chdir=>d})
          require "thread"
          #{total_count}.times do |i|
            open("test_thr_kill_count", "w") {|f| f.puts i }
            queue = Queue.new
            r, w = IO.pipe
            th = Thread.start {
              queue.push(nil)
              r.read 1
            }
            queue.pop
            th.kill
            th.join
          end
        _eom
      rescue Timeout::Error
        count = File.read("#{d}/test_thr_kill_count").to_i
        flunk "only #{count}/#{total_count} done in #{timeout} seconds."
      end
    }
  end

  def test_queue_push_return_value
    q = Queue.new
    retval = q.push(1)
    assert_same q, retval
  end

  def test_queue_clear_return_value
    q = Queue.new
    retval = q.clear
    assert_same q, retval
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

  def test_sized_queue_push_return_value
    q = SizedQueue.new(1)
    retval = q.push(1)
    assert_same q, retval
  end

  def test_sized_queue_clear_return_value
    q = SizedQueue.new(1)
    retval = q.clear
    assert_same q, retval
  end

  def test_sized_queue_throttle
    q = SizedQueue.new(1)
    i = 0
    consumer = Thread.new do
      while q.pop
        i += 1
        Thread.pass
      end
    end
    nprod = 4
    npush = 100

    producer = nprod.times.map do
      Thread.new do
        npush.times { q.push(true) }
      end
    end
    producer.each(&:join)
    q.push(nil)
    consumer.join
    assert_equal(nprod * npush, i)
  end

  def test_queue_thread_raise
    q = Queue.new
    th1 = Thread.new do
      begin
        q.pop
      rescue RuntimeError
        sleep
      end
    end
    th2 = Thread.new do
      sleep 0.1
      q.pop
    end
    sleep 0.1
    th1.raise
    sleep 0.1
    q << :s
    assert_nothing_raised(Timeout::Error) do
      timeout(1) { th2.join }
    end
  ensure
    [th1, th2].each do |th|
      if th and th.alive?
        th.wakeup
        th.join
      end
    end
  end

  def test_dup
    bug9440 = '[ruby-core:59961] [Bug #9440]'
    q = Queue.new
    assert_raise(NoMethodError, bug9440) do
      q.dup
    end
  end

  (DumpableQueue = Queue.dup).class_eval {remove_method :marshal_dump}

  def test_dump
    bug9674 = '[ruby-core:61677] [Bug #9674]'
    q = Queue.new
    assert_raise_with_message(TypeError, /#{Queue}/, bug9674) do
      Marshal.dump(q)
    end

    sq = SizedQueue.new(1)
    assert_raise_with_message(TypeError, /#{SizedQueue}/, bug9674) do
      Marshal.dump(sq)
    end

    q = DumpableQueue.new
    assert_raise_with_message(TypeError, /internal Array/, bug9674) do
      Marshal.dump(q)
    end
  end

  def test_queue_with_trap
    assert_in_out_err([], <<-INPUT, %w(INT INT exit), [])
      q = Queue.new
      trap(:INT){
        q.push 'INT'
      }
      Thread.new{
        loop{
          Process.kill :INT, $$
        }
      }
      puts q.pop
      puts q.pop
      puts 'exit'
    INPUT
  end
end
