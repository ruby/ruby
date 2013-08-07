require 'test/unit'
require 'thread'
require 'tmpdir'
require_relative '../ruby/envutil'

class TestQueue < Test::Unit::TestCase
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
  end

  def test_queue_pop_interrupt
    q = Queue.new
    t1 = Thread.new { q.pop }
    sleep 0.01 until t1.stop?
    t1.kill.join
    assert_equal(0, q.num_waiting)
  end

  def test_sized_queue_pop_interrupt
    q = SizedQueue.new(1)
    t1 = Thread.new { q.pop }
    sleep 0.01 until t1.stop?
    t1.kill.join
    assert_equal(0, q.num_waiting)
  end

  def test_sized_queue_push_interrupt
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

  def test_queue_each
    q = Queue.new
    q.push(1)
    q.push(2)
    results = []
    doubler = Thread.new do
      q.each do |n|
        results << n + n
      end
    end
    sleep 0.01 until doubler.stop?
    assert_equal [2, 4], results
    q.push(3)
    sleep 0.01 until doubler.stop?
    assert_equal [2, 4, 6], results
  end

  def test_queue_each_break
    q = Queue.new
    q.push(1)
    q.push(:stop)
    q.push(2)
    results = []
    doubler = Thread.new do
      q.each do |n|
        break if n == :stop
        results << n + n
      end
    end
    doubler.join
    assert_equal [2], results
    assert_equal 2, q.pop
  end

  def test_queue_each_enumerator
    q = Queue.new
    q.push(1)
    q.push(2)
    e = q.each
    assert_instance_of Enumerator, e
    assert_equal 2, e.size
    assert_equal 1, e.next
    assert_equal 2, e.next
    assert_equal 0, e.size
  end

  def test_queue_each_blocking_passes_thread_errors_through
    q = Queue.new
    q.push(1)
    doubler = Thread.new do
      q.each(false) do |n|
        raise ThreadError
      end
    end
    assert_raises(ThreadError) do
      doubler.join
    end
  end

  def test_queue_each_nonblock
    q = Queue.new
    q.push(1)
    q.push(2)
    results = []
    doubler = Thread.new do
      q.each(true) do |n|
        results << n + n
      end
    end
    doubler.abort_on_exception = true
    sleep 0.01 until doubler.stop?
    assert_equal [2, 4], results
    assert !doubler.alive?, "Thread should have ended"
  end
end
