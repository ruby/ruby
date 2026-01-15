# frozen_string_literal: false
require 'envutil'
require_relative "helper"

class TestThreadInstrumentation < Test::Unit::TestCase
  include ThreadInstrumentation::TestHelper

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

  def test_thread_pass_single_thread
    full_timeline = record do
      Thread.pass
    end
    assert_equal [], timeline_for(Thread.current, full_timeline)
  end

  def test_thread_pass_multi_thread
    thread = Thread.new do
      cpu_bound_work(0.5)
    end

    full_timeline = record do
      Thread.pass
    end

    assert_equal %i(suspended ready resumed), timeline_for(Thread.current, full_timeline)
  ensure
    thread&.kill
    thread&.join
  end

  def test_multi_thread_timeline
    threads = nil
    full_timeline = record do
      threads = threaded_cpu_bound_work(1.0)
      results = threads.map(&:value)
      results.each do |r|
        refute_equal false, r
      end
      assert_equal [false] * THREADS_COUNT, threads.map(&:status)
    end

    threads.each do |thread|
      timeline = timeline_for(thread, full_timeline)
      assert_consistent_timeline(timeline)
      assert_operator timeline.count(:suspended), :>=, 1, "Expected threads to yield suspended at least once: #{timeline.inspect}"
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

  def test_blocking_on_ractor
    assert_ractor(<<-"RUBY", require_relative: "helper", require: "-test-/thread/instrumentation")
      include ThreadInstrumentation::TestHelper

      ractor = Ractor.new {
        Ractor.receive # wait until woke
        Thread.current
      }

      # Wait for the main thread to block, then wake the ractor
      Thread.new do
        while Thread.main.status != "sleep"
          Thread.pass
        end
        ractor.send true
      end

      full_timeline = record do
        ractor.value
      end

      timeline = timeline_for(Thread.current, full_timeline)
      assert_consistent_timeline(timeline)
      assert_equal %i(suspended ready resumed), timeline
    RUBY
  end

  def test_sleeping_inside_ractor
    omit "This test is flaky and intermittently failing now on ModGC workflow" if ENV['GITHUB_WORKFLOW'] == 'ModGC'

    assert_ractor(<<-"RUBY", require_relative: "helper", require: "-test-/thread/instrumentation")
      include ThreadInstrumentation::TestHelper

      thread = nil

      full_timeline = record do
        thread = Ractor.new{
          sleep 0.1
          Thread.current
        }.value
        sleep 0.1
      end

      timeline = timeline_for(thread, full_timeline)
      assert_consistent_timeline(timeline)
      assert_equal %i(started ready resumed suspended ready resumed suspended exited), timeline
    RUBY
  end

  def test_thread_blocked_forever_on_mutex
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
    assert_equal %i(started ready resumed suspended), timeline
  end

  def test_thread_blocked_temporarily_on_mutex
    mutex = Mutex.new
    mutex.lock
    thread = nil

    full_timeline = record do
      thread = Thread.new do
        mutex.lock
      end
      10.times { Thread.pass }
      sleep 0.1
      mutex.unlock
      10.times { Thread.pass }
      sleep 0.1
    end

    thread.join

    timeline = timeline_for(thread, full_timeline)
    assert_consistent_timeline(timeline)
    assert_equal %i(started ready resumed suspended ready resumed suspended exited), timeline
  end

  def test_thread_instrumentation_fork_safe
    skip "No fork()" unless Process.respond_to?(:fork)

    thread_statuses = full_timeline = nil
    IO.popen("-") do |read_pipe|
      if read_pipe
        thread_statuses = Marshal.load(read_pipe)
        full_timeline = Marshal.load(read_pipe)
      else
        threads = threaded_cpu_bound_work.each(&:join)
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

  def fib(n = 30)
    return n if n <= 1
    fib(n-1) + fib(n-2)
  end

  def cpu_bound_work(duration)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + duration
    i = 0
    while deadline > Process.clock_gettime(Process::CLOCK_MONOTONIC)
      fib(25)
      i += 1
    end
    i > 0 ? i : false
  end

  def threaded_cpu_bound_work(duration = 0.5)
    THREADS_COUNT.times.map do
      Thread.new do
        cpu_bound_work(duration)
      end
    end
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
