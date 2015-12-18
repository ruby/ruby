# frozen_string_literal: false
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

    # close the queue the old way to test for backwards-compatibility
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
      Timeout.timeout(1) { th2.join }
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

  def test_close
    [->{Queue.new}, ->{SizedQueue.new 3}].each do |qcreate|
      q = qcreate.call
      assert_equal false, q.closed?
      q << :something
      assert_equal q, q.close
      assert q.closed?
      assert_raise_with_message(ClosedQueueError, /closed/){q << :nothing}
      assert_equal q.pop, :something
      assert_nil q.pop
      assert_nil q.pop
      # non-blocking
      assert_raise_with_message(ThreadError, /queue empty/){q.pop(non_block=true)}
    end
  end

  # test that waiting producers are woken up on close
  def close_wakeup( num_items, num_threads, &qcreate )
    raise "This test won't work with num_items(#{num_items}) >= num_threads(#{num_threads})" if num_items >= num_threads

    # create the Queue
    q = yield
    threads = num_threads.times.map{Thread.new{q.pop}}
    num_items.times{|i| q << i}

    # wait until queue empty
    (Thread.pass; sleep 0.01) until q.size == 0

    # close the queue so remaining threads will wake up
    q.close

    # wait for them to go away
    Thread.pass until threads.all?{|thr| thr.status == false}

    # check that they've gone away. Convert nil to -1 so we can sort and do the comparison
    expected_values = [-1] * (num_threads - num_items) + num_items.times.to_a
    assert_equal expected_values, threads.map{|thr| thr.value || -1 }.sort
  end

  def test_queue_close_wakeup
    close_wakeup(15, 18){Queue.new}
  end

  def test_size_queue_close_wakeup
    close_wakeup(5, 8){SizedQueue.new 9}
  end

  def test_sized_queue_one_closed_interrupt
    q = SizedQueue.new 1
    q << :one
    t1 = Thread.new { q << :two }
    sleep 0.01 until t1.stop?
    q.close

    t1.kill.join
    assert_equal 1, q.size
    assert_equal :one, q.pop
    assert q.empty?, "queue not empty"
  end

  # make sure that shutdown state is handled properly by empty? for the non-blocking case
  def test_empty_non_blocking
    return
    q = SizedQueue.new 3
    3.times{|i| q << i}

    # these all block cos the queue is full
    prod_threads = 4.times.map{|i| Thread.new{q << 3+i}}
    sleep 0.01 until prod_threads.all?{|thr| thr.status == 'sleep'}
    q.close

    items = []
    # sometimes empty? is false but pop will raise ThreadError('empty'),
    # meaning a value is not immediately available but will be soon.
    until q.empty?
      items << q.pop(non_block=true) rescue nil
    end
    items.compact!

    assert_equal 7.times.to_a, items.sort
    assert q.empty?
  end

  def test_sized_queue_closed_push_non_blocking
    q = SizedQueue.new 7
    q.close
    assert_raise_with_message(ClosedQueueError, /queue closed/){q.push(non_block=true)}
  end

  def test_blocked_pushers
    q = SizedQueue.new 3
    prod_threads = 6.times.map do |i|
      thr = Thread.new{q << i}; thr[:pc] = i; thr
    end

    # wait until some producer threads have finished, and the other 3 are blocked
    sleep 0.01 while prod_threads.reject{|t| t.status}.count < 3
    # this would ensure that all producer threads call push before close
    # sleep 0.01 while prod_threads.select{|t| t.status == 'sleep'}.count < 3
    q.close

    # more than prod_threads
    cons_threads = 10.times.map do |i|
      thr = Thread.new{q.pop}; thr[:pc] = i; thr
    end

    # values that came from the queue
    popped_values = cons_threads.map &:value

    # wait untl all threads have finished
    sleep 0.01 until prod_threads.find_all{|t| t.status}.count == 0

    # pick only the producer threads that got in before close
    successful_prod_threads = prod_threads.reject{|thr| thr.status == nil}
    assert_nothing_raised{ successful_prod_threads.map(&:value) }

    # the producer threads that tried to push after q.close should all fail
    unsuccessful_prod_threads = prod_threads - successful_prod_threads
    unsuccessful_prod_threads.each do |thr|
      assert_raise(ClosedQueueError){ thr.value }
    end

    assert_equal cons_threads.size, popped_values.size
    assert_equal 0, q.size

    # check that consumer threads with values match producers that called push before close
    assert_equal successful_prod_threads.map{|thr| thr[:pc]}, popped_values.compact.sort
    assert_nil q.pop
  end

  def test_deny_pushers
    [->{Queue.new}, ->{SizedQueue.new 3}].each do |qcreate|
      prod_threads = nil
      q = qcreate[]
      synq = Queue.new
      producers_start = Thread.new do
        prod_threads = 20.times.map do |i|
          Thread.new{ synq.pop; q << i }
        end
      end
      q.close
      synq.close # start producer threads

      # wait for all threads to be finished, because of exceptions
      # NOTE: thr.status will be nil (raised) or false (terminated)
      sleep 0.01 until prod_threads&.all?{|thr| !thr.status}

      # check that all threads failed to call push
      prod_threads.each do |thr|
        assert_kind_of ClosedQueueError, (thr.value rescue $!)
      end
    end
  end

  # size should account for waiting pushers during shutdown
  def sized_queue_size_close
    q = SizedQueue.new 4
    4.times{|i| q << i}
    Thread.new{ q << 5 }
    Thread.new{ q << 6 }
    assert_equal 4, q.size
    assert_equal 4, q.items
    q.close
    assert_equal 6, q.size
    assert_equal 4, q.items
  end

  def test_blocked_pushers_empty
    q = SizedQueue.new 3
    prod_threads = 6.times.map do |i|
      Thread.new{ q << i}
    end

    # this ensures that all producer threads call push before close
    sleep 0.01 while prod_threads.select{|t| t.status == 'sleep'}.count < 3
    q.close

    ary = []
    until q.empty?
      ary << q.pop
    end
    assert_equal 0, q.size

    assert_equal 3, ary.size
    ary.each{|e| assert [0,1,2,3,4,5].include?(e)}
    assert_nil q.pop

    prod_threads.each{|t|
      begin
        t.join
      rescue => e
      end
    }
  end

  # test thread wakeup on one-element SizedQueue with close
  def test_one_element_sized_queue
    q = SizedQueue.new 1
    t = Thread.new{ q.pop }
    q.close
    assert_nil t.value
  end

  def test_close_twice
    [->{Queue.new}, ->{SizedQueue.new 3}].each do |qcreate|
      q = qcreate[]
      q.close
      assert_nothing_raised(ClosedQueueError){q.close}
    end
  end

  def test_queue_close_multi_multi
    q = SizedQueue.new rand(800..1200)

    count_items = rand(3000..5000)
    count_producers = rand(10..20)

    producers = count_producers.times.map do
      Thread.new do
        sleep(rand / 100)
        count_items.times{|i| q << [i,"#{i} for #{Thread.current.inspect}"]}
      end
    end

    consumers = rand(7..12).times.map do
      Thread.new do
        count = 0
        while e = q.pop
          i, st = e
          count += 1 if i.is_a?(Fixnum) && st.is_a?(String)
        end
        count
      end
    end

    # No dead or finished threads
    assert (consumers + producers).all?{|thr| thr.status =~ /\Arun|sleep\Z/}, 'no threads runnning'

    # just exercising the concurrency of the support methods.
    counter = Thread.new do
      until q.closed? && q.empty?
        raise if q.size > q.max
        # otherwise this exercise causes too much contention on the lock
        sleep 0.01
      end
    end

    producers.each &:join
    q.close

    # results not randomly distributed. Not sure why.
    # consumers.map{|thr| thr.value}.each do |x|
    #   assert_not_equal 0, x
    # end

    all_items_count = consumers.map{|thr| thr.value}.inject(:+)
    assert_equal count_items * count_producers, all_items_count

    # don't leak this thread
    assert_nothing_raised{counter.join}
  end
end
