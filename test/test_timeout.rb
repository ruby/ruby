# frozen_string_literal: false
require 'test/unit'
require 'timeout'

class TestTimeout < Test::Unit::TestCase

  private def kill_timeout_thread
    thread = Timeout.const_get(:State).instance.instance_variable_get(:@timeout_thread)
    if thread
      thread.kill
      thread.join
    end
  end

  def test_public_methods
    assert_equal [:timeout], Timeout.private_instance_methods(false)
    assert_equal [], Timeout.public_instance_methods(false)

    assert_equal [:timeout], Timeout.singleton_class.public_instance_methods(false)

    assert_equal [:Error, :ExitException, :VERSION], Timeout.constants.sort
  end

  def test_work_is_done_in_same_thread_as_caller
    assert_equal Thread.current, Timeout.timeout(10){ Thread.current }
  end

  def test_work_is_done_in_same_fiber_as_caller
    require 'fiber' # needed for ruby 3.0 and lower
    assert_equal Fiber.current, Timeout.timeout(10){ Fiber.current }
  end

  def test_non_timing_out_code_is_successful
    assert_nothing_raised do
      assert_equal :ok, Timeout.timeout(1){ :ok }
    end
  end

  def test_allows_zero_seconds
    assert_nothing_raised do
      assert_equal :ok, Timeout.timeout(0){:ok}
    end
  end

  def test_allows_nil_seconds
    assert_nothing_raised do
      assert_equal :ok, Timeout.timeout(nil){:ok}
    end
  end

  def test_raise_for_neg_second
    assert_raise(ArgumentError) do
      Timeout.timeout(-1) { sleep(0.01) }
    end
  end

  def test_included
    c = Class.new do
      include Timeout
      def test
        timeout(1) { :ok }
      end
    end
    assert_nothing_raised do
      assert_equal :ok, c.new.test
    end
  end

  def test_yield_param
    assert_equal [5, :ok], Timeout.timeout(5){|s| [s, :ok] }
  end

  def test_queue
    q = Thread::Queue.new
    assert_raise(Timeout::Error, "[ruby-dev:32935]") {
      Timeout.timeout(0.01) { q.pop }
    }
  end

  def test_timeout
    assert_raise(Timeout::Error) do
      Timeout.timeout(0.1) {
        nil while true
      }
    end
  end

  def test_nested_timeout
    a = nil
    assert_raise(Timeout::Error) do
      Timeout.timeout(0.1) {
        Timeout.timeout(30) {
          nil while true
        }
        a = 1
      }
    end
    assert_nil a
  end

  class MyNewErrorOuter < StandardError; end
  class MyNewErrorInner < StandardError; end

  # DOES NOT fail with
  # -        raise new(message) if exc.equal?(e)
  # +        raise new(message) if exc.class == e.class
  def test_nested_timeout_error_identity
    begin
      Timeout.timeout(0.1, MyNewErrorOuter) {
        Timeout.timeout(30, MyNewErrorInner) {
          nil while true
        }
      }
    rescue => e
      assert e.class == MyNewErrorOuter
    end
  end

  # DOES fail with
  # -        raise new(message) if exc.equal?(e)
  # +        raise new(message) if exc.class == e.class
  def test_nested_timeout_which_error_bubbles_up
    raised_exception = nil
    begin
      Timeout.timeout(0.1) {
        Timeout.timeout(1) {
          raise Timeout::ExitException.new("inner message")
        }
      }
    rescue Exception => e
      raised_exception = e
    end

    assert_equal 'inner message', raised_exception.message
  end

  def test_cannot_convert_into_time_interval
    bug3168 = '[ruby-dev:41010]'
    def (n = Object.new).zero?; false; end
    assert_raise(ArgumentError, bug3168) {Timeout.timeout(n) { sleep 0.1 }}
  end

  def test_skip_rescue_standarderror
    e = nil
    assert_raise_with_message(Timeout::Error, /execution expired/) do
      Timeout.timeout 0.01 do
        begin
          sleep 3
        rescue => e
          flunk "should not see any exception but saw #{e.inspect}"
        end
      end
    end
  end

  def test_raises_exception_internally
    e = nil
    assert_raise_with_message(Timeout::Error, /execution expired/) do
      Timeout.timeout 0.01 do
        begin
          sleep 3
        rescue Exception => exc
          e = exc
          raise
        end
      end
    end
    assert_equal Timeout::ExitException, e.class
  end

  def test_rescue_exit
    exc = Class.new(RuntimeError)
    e = nil
    assert_nothing_raised(exc) do
      Timeout.timeout 0.01, exc do
        begin
          sleep 3
        rescue exc => e
        end
      end
    end
    assert_raise_with_message(exc, 'execution expired') {raise e if e}
  end

  def test_custom_exception
    bug9354 = '[ruby-core:59511] [Bug #9354]'
    err = Class.new(StandardError) do
      def initialize(msg) super end
    end
    assert_nothing_raised(ArgumentError, bug9354) do
      assert_equal(:ok, Timeout.timeout(100, err) {:ok})
    end
    assert_raise_with_message(err, 'execution expired') do
      Timeout.timeout 0.01, err do
        sleep 3
      end
    end
    assert_raise_with_message(err, /connection to ruby-lang.org expired/) do
      Timeout.timeout 0.01, err, "connection to ruby-lang.org expired" do
        sleep 3
      end
    end
  end

  def test_exit_exception
    assert_raise_with_message(Timeout::Error, "boon") do
      Timeout.timeout(10, Timeout::Error) do
        raise Timeout::Error, "boon"
      end
    end
  end

  def test_raise_with_message
    bug17812 = '[ruby-core:103502] [Bug #17812]: Timeout::Error doesn\'t let two-argument raise() set a new message'
    exc = Timeout::Error.new('foo')
    assert_raise_with_message(Timeout::Error, 'bar', bug17812) do
      raise exc, 'bar'
    end
  end

  def test_enumerator_next
    bug9380 = '[ruby-dev:47872] [Bug #9380]: timeout in Enumerator#next'
    e = (o=Object.new).to_enum
    def o.each
      sleep
    end
    assert_raise_with_message(Timeout::Error, 'execution expired', bug9380) do
      Timeout.timeout(0.01) {e.next}
    end
  end

  def test_handle_interrupt_with_exception_class
    bug11344 = '[ruby-dev:49179] [Bug #11344]'
    ok = false
    assert_raise(Timeout::Error) {
      Thread.handle_interrupt(Timeout::Error => :never) {
        Timeout.timeout(0.01, Timeout::Error) {
          sleep 0.2
          ok = true
          Thread.handle_interrupt(Timeout::Error => :on_blocking) {
            sleep 0.2
            raise "unreachable"
          }
        }
      }
    }
    assert(ok, bug11344)
  end

  def test_handle_interrupt
    bug11344 = '[ruby-dev:49179] [Bug #11344]'
    ok = false
    assert_raise(Timeout::Error) {
      Thread.handle_interrupt(Timeout::ExitException => :never) {
        Timeout.timeout(0.01) {
          sleep 0.2
          ok = true
          Thread.handle_interrupt(Timeout::ExitException => :on_blocking) {
            sleep 0.2
            raise "unreachable"
          }
        }
      }
    }
    assert(ok, bug11344)
  end

  def test_handle_interrupt_with_interrupt_mask_inheritance
    issue = 'https://github.com/ruby/timeout/issues/41'

    [
      -> {}, # not blocking so no opportunity to interrupt
      -> { sleep 5 }
    ].each_with_index do |body, idx|
      # We need to create a new Timeout thread
      kill_timeout_thread

      # Create the timeout thread under a handle_interrupt(:never)
      # due to the interrupt mask being inherited
      Thread.handle_interrupt(Object => :never) {
        assert_equal :ok, Timeout.timeout(1) { :ok }
      }

      # Ensure a simple timeout works and the interrupt mask was not inherited
      assert_raise(Timeout::Error) {
        Timeout.timeout(0.001) { sleep 1 }
      }

      r = []
      # This raises Timeout::ExitException and not Timeout::Error for the non-blocking body
      # because of the handle_interrupt(:never) which delays raising Timeout::ExitException
      # on the main thread until getting outside of that handle_interrupt(:never) call.
      # For this reason we document handle_interrupt(Timeout::ExitException) should not be used.
      exc = idx == 0 ? Timeout::ExitException : Timeout::Error
      assert_raise(exc) {
        Thread.handle_interrupt(Timeout::ExitException => :never) {
          Timeout.timeout(0.1) do
            sleep 0.2
            r << :sleep_before_done
            Thread.handle_interrupt(Timeout::ExitException => :on_blocking) {
              r << :body
              body.call
            }
          ensure
            sleep 0.2
            r << :ensure_sleep_done
          end
        }
      }
      assert_equal([:sleep_before_done, :body, :ensure_sleep_done], r, issue)
    end
  end

  # Same as above but with an exception class
  def test_handle_interrupt_with_interrupt_mask_inheritance_with_exception_class
    issue = 'https://github.com/ruby/timeout/issues/41'

    [
      -> {}, # not blocking so no opportunity to interrupt
      -> { sleep 5 }
    ].each do |body|
      # We need to create a new Timeout thread
      kill_timeout_thread

      # Create the timeout thread under a handle_interrupt(:never)
      # due to the interrupt mask being inherited
      Thread.handle_interrupt(Object => :never) {
        assert_equal :ok, Timeout.timeout(1) { :ok }
      }

      # Ensure a simple timeout works and the interrupt mask was not inherited
      assert_raise(Timeout::Error) {
        Timeout.timeout(0.001) { sleep 1 }
      }

      r = []
      assert_raise(Timeout::Error) {
        Thread.handle_interrupt(Timeout::Error => :never) {
          Timeout.timeout(0.1, Timeout::Error) do
            sleep 0.2
            r << :sleep_before_done
            Thread.handle_interrupt(Timeout::Error => :on_blocking) {
              r << :body
              body.call
            }
          ensure
            sleep 0.2
            r << :ensure_sleep_done
          end
        }
      }
      assert_equal([:sleep_before_done, :body, :ensure_sleep_done], r, issue)
    end
  end

  def test_fork
    omit 'fork not supported' unless Process.respond_to?(:fork)
    r, w = IO.pipe
    pid = fork do
      r.close
      begin
        r = Timeout.timeout(0.01) { sleep 5 }
        w.write r.inspect
      rescue Timeout::Error
        w.write 'timeout'
      ensure
        w.close
      end
    end
    w.close
    Process.wait pid
    assert_equal 'timeout', r.read
    r.close
  end

  def test_threadgroup
    assert_separately(%w[-rtimeout], <<-'end;')
      tg = ThreadGroup.new
      thr = Thread.new do
        tg.add(Thread.current)
        Timeout.timeout(10){}
      end
      thr.join
      assert_equal [].to_s, tg.list.to_s
    end;
  end

  # https://github.com/ruby/timeout/issues/24
  def test_handling_enclosed_threadgroup
    assert_separately(%w[-rtimeout], <<-'end;')
      Thread.new {
        t = Thread.current
        group = ThreadGroup.new
        group.add(t)
        group.enclose

        assert_equal 42, Timeout.timeout(1) { 42 }
      }.join
    end;
  end

  def test_ractor
    assert_separately(%w[-rtimeout -W0], <<-'end;')
      r = Ractor.new do
        Timeout.timeout(1) { 42 }
      end.value

      assert_equal 42, r

      r = Ractor.new do
        begin
          Timeout.timeout(0.1) { sleep }
        rescue Timeout::Error
          :ok
        end
      end.value

      assert_equal :ok, r
    end;
  end if defined?(::Ractor) && RUBY_VERSION >= '4.0'

  def test_timeout_in_trap_handler
    # https://github.com/ruby/timeout/issues/17

    # Test as if this was the first timeout usage
    kill_timeout_thread

    rd, wr = IO.pipe

    signal = :TERM

    original_handler = trap(signal) do
      begin
        Timeout.timeout(0.1) do
          sleep 1
        end
      rescue Timeout::Error
        wr.write "OK"
        wr.close
      else
        wr.write "did not raise"
      ensure
        wr.close
      end
    end

    begin
      Process.kill signal, Process.pid

      assert_equal "OK", rd.read
      rd.close
    ensure
      trap(signal, original_handler)
    end
  end
end
