# frozen_string_literal: false

class TestThreadInstrumentation < Test::Unit::TestCase
  STARTED = 0
  READY = 1
  RESUMED = 2
  SUSPENDED = 3
  EXITED = 4
  FREED = 5

  if /mswin|mingw|bccwin/ =~ RUBY_PLATFORM
    def setup
      pend("No windows support")
    end
  else
    def setup
      require '-test-/thread/instrumentation'
      Bug::ThreadInstrumentation.reset_counters
    end

    def teardown
      Bug::ThreadInstrumentation::unregister_callback
      Bug::ThreadInstrumentation.reset_counters
    end
  end

  THREADS_COUNT = 3

  def test_thread_instrumentation
    Bug::ThreadInstrumentation::register_callback

    threads = threaded_cpu_work
    assert_equal [false] * THREADS_COUNT, threads.map(&:status)
    counters = Bug::ThreadInstrumentation.counters

    counters.each do |c|
      assert_predicate c, :nonzero?, "Call counters: #{counters.inspect}"
    end

    # It's possible that a joined thread didn't execute its EXIT hook yet.
    assert_in_delta THREADS_COUNT, counters[EXITED], 1
    assert_in_delta THREADS_COUNT, counters[FREED], 1
  end

  def test_thread_instrumentation_fork_safe
    skip "No fork()" unless Process.respond_to?(:fork)

    Bug::ThreadInstrumentation::register_callback

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

    assert_equal THREADS_COUNT, counters[STARTED]

    # It's possible that a joined thread didn't execute its EXIT hook yet.
    assert_in_delta THREADS_COUNT, counters[EXITED], 1
    assert_in_delta THREADS_COUNT, counters[FREED], 1
  end

  def test_thread_instrumentation_unregister
    assert Bug::ThreadInstrumentation::register_and_unregister_callbacks
  end

  def test_thread_local_counters
    Bug::ThreadInstrumentation::register_callback

    Thread.new {
      assert_equal [1, 1, 1, 0, 0], Bug::ThreadInstrumentation.local_counters
    }.join
  end

  private

  def cpu_work
    fibonacci(20)
  end

  def fibonacci(number)
    number <= 1 ? number : fibonacci(number - 1) + fibonacci(number - 2)
  end

  def spawn_threaded_cpu_work(thread_count = THREADS_COUNT)
    thread_count.times.map { Thread.new { cpu_work } }
  end

  def threaded_cpu_work(thread_count = THREADS_COUNT)
    spawn_threaded_cpu_work.each(&:join)
  end
end
