# frozen_string_literal: false
require 'envutil'

class TestThreadInstrumentation < Test::Unit::TestCase
  def setup
    pend("No windows support") if /mswin|mingw|bccwin/ =~ RUBY_PLATFORM

    require '-test-/thread/instrumentation'

    Thread.list.each do |thread|
      if thread != Thread.current
        thread.kill
        thread.join rescue nil
      end
    end
    assert_equal [Thread.current], Thread.list

    Bug::ThreadInstrumentation.reset_counters
    Bug::ThreadInstrumentation::register_callback
  end

  def teardown
    return if /mswin|mingw|bccwin/ =~ RUBY_PLATFORM
    Bug::ThreadInstrumentation::unregister_callback
  end

  THREADS_COUNT = 3

  def test_thread_instrumentation
    threads = threaded_cpu_work
    assert_equal [false] * THREADS_COUNT, threads.map(&:status)
    counters = Bug::ThreadInstrumentation.counters
    assert_join_counters(counters)
    assert_global_join_counters(counters)
  end

  def test_join_counters # Bug #18900
    thr = Thread.new { fib(30) }
    Bug::ThreadInstrumentation.reset_counters
    thr.join
    assert_join_counters(Bug::ThreadInstrumentation.local_counters)
  end

  def test_thread_instrumentation_fork_safe
    skip "No fork()" unless Process.respond_to?(:fork)

    thread_statuses = counters = nil
    IO.popen("-") do |read_pipe|
      if read_pipe
        thread_statuses = Marshal.load(read_pipe)
        counters = Marshal.load(read_pipe)
      else
        Bug::ThreadInstrumentation.reset_counters
        threads = threaded_cpu_work
        Marshal.dump(threads.map(&:status), STDOUT)
        Marshal.dump(Bug::ThreadInstrumentation.counters, STDOUT)
      end
    end
    assert_predicate $?, :success?

    assert_equal [false] * THREADS_COUNT, thread_statuses
    assert_join_counters(counters)
    assert_global_join_counters(counters)
  end

  def test_thread_instrumentation_unregister
    Bug::ThreadInstrumentation::unregister_callback
    assert Bug::ThreadInstrumentation::register_and_unregister_callbacks
  end

  private

  def fib(n = 20)
    return n if n <= 1
    fib(n-1) + fib(n-2)
  end

  def threaded_cpu_work(size = 20)
    THREADS_COUNT.times.map { Thread.new { fib(size) } }.each(&:join)
  end

  def assert_join_counters(counters)
    counters.each_with_index do |c, i|
      assert_operator c, :>, 0, "Call counters[#{i}]: #{counters.inspect}"
    end
  end

  def assert_global_join_counters(counters)
    assert_equal THREADS_COUNT, counters.first
  end
end
