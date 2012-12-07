require 'test/unit'
require 'timeout'
require 'thread'

class TestTimeout < Test::Unit::TestCase
  def test_queue
    q = Queue.new
    assert_raise(Timeout::Error, "[ruby-dev:32935]") {
      timeout(0.1) { q.pop }
    }
  end

  def test_timeout
    @flag = true
    Thread.start {
      sleep 0.1
      @flag = false
    }
    assert_nothing_raised("[ruby-dev:38319]") do
      Timeout.timeout(1) {
        sleep 0.01 while @flag
      }
    end
    assert !@flag, "[ruby-dev:38319]"
  end

  def test_cannot_convert_into_time_interval
    bug3168 = '[ruby-dev:41010]'
    def (n = Object.new).zero?; false; end
    assert_raise(TypeError, bug3168) {Timeout.timeout(n) { sleep 0.1 }}
  end

  def test_timeout_immediate
    begin
      t = Thread.new {
        Timeout.timeout(0.1, immediate: true) {
          # loop forever, but can be interrupted
          loop {}
        }
      }
      sleep 0.5
      t.raise RuntimeError
      assert_raise(Timeout::Error) {
        t.join
      }
    ensure
      t.kill if t.alive?
      begin
        t.join
      rescue Exception
      end
    end
  end

  def test_timeout_immediate2
    begin
      t = Thread.new {
        Timeout.timeout(0.1) {
          # loop forever, must not interrupted
          loop {}
        }
      }
      sleep 0.5
      t.raise RuntimeError
      assert_raise(Timeout::Error) {
        # deferred interrupt should raise
        t.join
      }
    ensure
      t.kill if t.alive?
      begin
        t.join
      rescue Exception
      end
    end
  end

  def test_timeout_blocking
    t0 = Time.now
    begin
      Timeout.timeout(0.1) {
        while true do
          t1 = Time.now
          break if t1 - t0 > 1
        end
        sleep 2
      }
    rescue Timeout::Error
    end
    t1 = Time.now
    assert (t1 - t0) >= 1
    assert (t1 - t0) < 2
  end
end
