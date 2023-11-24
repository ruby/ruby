# frozen_string_literal: false
require 'envutil'

class TestThreadInstrumentation < Test::Unit::TestCase
  def setup
    pend("No windows support") if /mswin|mingw|bccwin/ =~ RUBY_PLATFORM

    require '-test-/thread/instrumentation'

    cleanup_threads
  end

  def teardown
    return if /mswin|mingw|bccwin/ =~ RUBY_PLATFORM
    Bug::ThreadInstrumentation.unregister_callback
    cleanup_threads
  end

  THREADS_COUNT = 3

  def test_single_thread_timeline
    thread = nil
    full_timeline = record do
      thread = Thread.new { 1 + 1 }
      thread.join
    end
    assert_equal %i(started ready resumed suspended exited), timeline_for(thread, full_timeline)
  ensure
    thread&.kill
  end

  def test_muti_thread_timeline
    threads = nil
    full_timeline = record do
      threads = threaded_cpu_work
      fib(20)
      assert_equal [false] * THREADS_COUNT, threads.map(&:status)
    end


    threads.each do |thread|
      timeline = timeline_for(thread, full_timeline)
      assert_consistent_timeline(timeline)
    end

    timeline = timeline_for(Thread.current, full_timeline)
    assert_consistent_timeline(timeline)
  ensure
    threads&.each(&:kill)
  end

  def test_join_suspends # Bug #18900
    thread = other_thread = nil
    full_timeline = record do
      other_thread = Thread.new { sleep 0.3 }
      thread = Thread.new { other_thread.join }
      thread.join
    end

    timeline = timeline_for(thread, full_timeline)
    assert_consistent_timeline(timeline)
    assert_equal %i(started ready resumed suspended ready resumed suspended exited), timeline
  ensure
    other_thread&.kill
    thread&.kill
  end

  def test_io_release_gvl
    r, w = IO.pipe
    thread = nil
    full_timeline = record do
      thread = Thread.new do
        w.write("Hello\n")
      end
      thread.join
    end

    timeline = timeline_for(thread, full_timeline)
    assert_consistent_timeline(timeline)
    assert_equal %i(started ready resumed suspended ready resumed suspended exited), timeline
  ensure
    r&.close
    w&.close
  end

  def test_queue_releases_gvl
    queue1 = Queue.new
    queue2 = Queue.new

    thread = nil

    full_timeline = record do
      thread = Thread.new do
        queue1 << true
        queue2.pop
      end

      queue1.pop
      queue2 << true
      thread.join
    end

    timeline = timeline_for(thread, full_timeline)
    assert_consistent_timeline(timeline)
    assert_equal %i(started ready resumed suspended ready resumed suspended exited), timeline
  end

  def test_thread_blocked_forever
    mutex = Mutex.new
    mutex.lock
    thread = nil

    full_timeline = record do
      thread = Thread.new do
        mutex.lock
      end
      10.times { Thread.pass }
      sleep 0.1
    end

    mutex.unlock
    thread.join

    timeline = timeline_for(thread, full_timeline)
    assert_consistent_timeline(timeline)
    assert_equal %i(started ready resumed), timeline
  end

  def test_thread_instrumentation_fork_safe
    skip "No fork()" unless Process.respond_to?(:fork)

    thread_statuses = full_timeline = nil
    IO.popen("-") do |read_pipe|
      if read_pipe
        thread_statuses = Marshal.load(read_pipe)
        full_timeline = Marshal.load(read_pipe)
      else
        threads = threaded_cpu_work
        Marshal.dump(threads.map(&:status), STDOUT)
        full_timeline = Bug::ThreadInstrumentation.unregister_callback.map { |t, e| [t.to_s, e ] }
        Marshal.dump(full_timeline, STDOUT)
      end
    end
    assert_predicate $?, :success?

    assert_equal [false] * THREADS_COUNT, thread_statuses
    thread_names = full_timeline.map(&:first).uniq
    thread_names.each do |thread_name|
      assert_consistent_timeline(timeline_for(thread_name, full_timeline))
    end
  end

  def test_thread_instrumentation_unregister
    assert Bug::ThreadInstrumentation::register_and_unregister_callbacks
  end

  private

  def record
    Bug::ThreadInstrumentation.register_callback
    yield
  ensure
    timeline = Bug::ThreadInstrumentation.unregister_callback
    if $!
      raise
    else
      return timeline
    end
  end

  def assert_consistent_timeline(events)
    refute_predicate events, :empty?

    previous_event = nil
    events.each do |event|
      refute_equal :exited, previous_event, "`exited` must be the final event: #{events.inspect}"
      case event
      when :started
        assert_nil previous_event, "`started` must be the first event: #{events.inspect}"
      when :ready
        unless previous_event.nil?
          assert %i(started suspended).include?(previous_event), "`ready` must be preceded by `started` or `suspended`: #{events.inspect}"
        end
      when :resumed
        unless previous_event.nil?
          assert_equal :ready, previous_event, "`resumed` must be preceded by `ready`: #{events.inspect}"
        end
      when :suspended
        unless previous_event.nil?
          assert_equal :resumed, previous_event, "`suspended` must be preceded by `resumed`: #{events.inspect}"
        end
      when :exited
        unless previous_event.nil?
          assert %i(resumed suspended).include?(previous_event), "`exited` must be preceded by `resumed` or `suspended`: #{events.inspect}"
        end
      end
      previous_event = event
    end
  end

  def timeline_for(thread, timeline)
    timeline.select { |t, _| t == thread }.map(&:last)
  end

  def fib(n = 20)
    return n if n <= 1
    fib(n-1) + fib(n-2)
  end

  def threaded_cpu_work(size = 20)
    THREADS_COUNT.times.map { Thread.new { fib(size) } }.each(&:join)
  end

  def cleanup_threads
    Thread.list.each do |thread|
      if thread != Thread.current
        thread.kill
        thread.join rescue nil
      end
    end
    assert_equal [Thread.current], Thread.list
  end
end
