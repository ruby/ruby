# frozen_string_literal: false
class TestThreadInstrumentation < Test::Unit::TestCase
  def setup
    pend("TODO: No windows support yet") if /mswin|mingw|bccwin/ =~ RUBY_PLATFORM
  end

  def test_thread_instrumentation
    require '-test-/thread/instrumentation'
    Bug::ThreadInstrumentation.reset_counters
    Bug::ThreadInstrumentation::register_callback

    begin
      threaded_cpu_work
      counters = Bug::ThreadInstrumentation.counters
      counters.each do |c|
        assert_predicate c,:nonzero?, "Call counters: #{counters.inspect}"
      end
    ensure
      Bug::ThreadInstrumentation::unregister_callback
    end
  end

  def test_thread_instrumentation_fork_safe
    skip "No fork()" unless Process.respond_to?(:fork)

    require '-test-/thread/instrumentation'
    Bug::ThreadInstrumentation::register_callback

    read_pipe, write_pipe = IO.pipe

    begin
      pid = fork do
        Bug::ThreadInstrumentation.reset_counters
        threaded_cpu_work

        write_pipe.write(Marshal.dump(Bug::ThreadInstrumentation.counters))
        write_pipe.close
        exit!(0)
      end
      write_pipe.close
      _, status = Process.wait2(pid)
      assert_predicate status, :success?

      counters = Marshal.load(read_pipe)
      read_pipe.close
      counters.each do |c|
        assert_predicate c, :nonzero?, "Call counters: #{counters.inspect}"
      end

      assert_equal counters.first, counters.last # exited as many times as we entered
    ensure
      Bug::ThreadInstrumentation::unregister_callback
    end
  end

  def test_thread_instrumentation_unregister
    require '-test-/thread/instrumentation'
    assert Bug::ThreadInstrumentation::register_and_unregister_callbacks
  end

  private

  def threaded_cpu_work
    5.times.map { Thread.new { 100.times { |i| i + i } } }.each(&:join)
  end
end
