# frozen_string_literal: false
require 'test/unit'
require 'timeout'

class TestTimeout < Test::Unit::TestCase

  def test_non_timing_out_code_is_successful
    assert_nothing_raised do
      assert_equal :ok, Timeout.timeout(1){ :ok }
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

  def test_cannot_convert_into_time_interval
    bug3168 = '[ruby-dev:41010]'
    def (n = Object.new).zero?; false; end
    assert_raise(TypeError, bug3168) {Timeout.timeout(n) { sleep 0.1 }}
  end

  def test_skip_rescue
    bug8730 = '[Bug #8730]'
    e = nil
    assert_raise_with_message(Timeout::Error, /execution expired/, bug8730) do
      Timeout.timeout 0.01 do
        begin
          sleep 3
        rescue Exception => e
          flunk "should not see any exception but saw #{e.inspect}"
        end
      end
    end
    assert_nil(e, bug8730)
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

  def test_handle_interrupt
    bug11344 = '[ruby-dev:49179] [Bug #11344]'
    ok = false
    assert_raise(Timeout::Error) {
      Thread.handle_interrupt(Timeout::Error => :never) {
        Timeout.timeout(0.01) {
          sleep 0.2
          ok = true
          Thread.handle_interrupt(Timeout::Error => :on_blocking) {
            sleep 0.2
          }
        }
      }
    }
    assert(ok, bug11344)
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

end
