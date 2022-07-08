# frozen_string_literal: false
require 'envutil'

class TestThreadInstrumentation < Test::Unit::TestCase
  def setup
    pend("No windows support") if /mswin|mingw|bccwin/ =~ RUBY_PLATFORM

    require '-test-/thread/instrumentation'
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
    counters.each do |c|
      assert_predicate c, :nonzero?, "Call counters: #{counters.inspect}"
    end

    assert_equal THREADS_COUNT, counters.first
    assert_in_delta THREADS_COUNT, counters.last, 1 # It's possible that a thread didn't execute its EXIT hook yet.
  end

  def test_join_counters # Bug #18900
    thr = Thread.new { fib(30) }
    Bug::ThreadInstrumentation.reset_counters
    thr.join
    Bug::ThreadInstrumentation.local_counters.each_with_index do |counter, index|
      assert_operator counter, :>, 0, "counter[#{index}]"
    end
  end

  def test_thread_instrumentation_fork_safe
    skip "No fork()" unless Process.respond_to?(:fork)

    read_pipe, write_pipe = IO.pipe

    pid = fork do
      Bug::ThreadInstrumentation.reset_counters
      threads = threaded_cpu_work
      write_pipe.write(Marshal.dump(threads.map(&:status)))
      write_pipe.write(Marshal.dump(Bug::ThreadInstrumentation.counters))
      write_pipe.close
      exit!(0)
    end
    write_pipe.close
    _, status = Process.wait2(pid)
    assert_predicate status, :success?

    thread_statuses = Marshal.load(read_pipe)
    assert_equal [false] * THREADS_COUNT, thread_statuses

    counters = Marshal.load(read_pipe)
    read_pipe.close
    counters.each do |c|
      assert_predicate c, :nonzero?, "Call counters: #{counters.inspect}"
    end

    assert_equal THREADS_COUNT, counters.first
    assert_in_delta THREADS_COUNT, counters.last, 1 # It's possible that a thread didn't execute its EXIT hook yet.
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
end
