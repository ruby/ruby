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
      threads = 5.times.map { Thread.new { sleep 0.05; 1 + 1; sleep 0.02 } }
      threads.each(&:join)
      Bug::ThreadInstrumentation.counters.each do |c|
        assert_predicate c,:nonzero?
      end
    ensure
      Bug::ThreadInstrumentation::unregister_callback
    end
  end

  def test_thread_instrumentation_fork_safe
    skip "No fork()" unless Process.respond_to?(:fork)

    require '-test-/thread/instrumentation'
    Bug::ThreadInstrumentation::register_callback

    begin
      pid = fork do
        Bug::ThreadInstrumentation.reset_counters
        threads = 5.times.map { Thread.new { sleep 0.05; 1 + 1; sleep 0.02 } }
        threads.each(&:join)
        Bug::ThreadInstrumentation.counters.each do |c|
          assert_predicate c,:nonzero?
        end
      end
      _, status = Process.wait2(pid)
      assert_predicate status, :success?
    ensure
      Bug::ThreadInstrumentation::unregister_callback
    end
  end

  def test_thread_instrumentation_unregister
    require '-test-/thread/instrumentation'
    assert Bug::ThreadInstrumentation::register_and_unregister_callbacks
  end
end

