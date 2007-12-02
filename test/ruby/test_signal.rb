require 'test/unit'
require 'timeout'

class TestSignal < Test::Unit::TestCase
  def have_fork?
    begin
      Process.fork {}
      return true
    rescue NotImplementedError
      return false
    end
  end

  def test_signal
    return unless Process.respond_to?(:kill)
    begin
      x = 0
      oldtrap = Signal.trap(:INT) {|sig| x = 2 }
      Process.kill :INT, Process.pid
      sleep 0.1
      assert_equal 2, x

      Signal.trap(:INT) { raise "Interrupt" }
      ex = assert_raises(RuntimeError) {
        Process.kill :INT, Process.pid
        sleep 0.1
      }
      assert_kind_of Exception, ex
      assert_match(/Interrupt/, ex.message)
    ensure
      Signal.trap :INT, oldtrap if oldtrap
    end
  end

  def test_exit_action
    return unless have_fork?	# snip this test
    begin
      r, w = IO.pipe
      r0, w0 = IO.pipe
      pid = Process.fork {
        Signal.trap(:USR1, "EXIT")
        w0.close
        w.syswrite("a")
        Thread.start { Thread.pass }
        r0.sysread(4096)
      }
      r.sysread(1)
      sleep 0.1
      assert_nothing_raised("[ruby-dev:26128]") {
        Process.kill(:USR1, pid)
        begin
          Timeout.timeout(3) {
            Process.waitpid pid
          }
        rescue Timeout::Error
          Process.kill(:TERM, pid)
          raise
        end
      }
    ensure
      r.close
      w.close
      r0.close
      w0.close
    end
  end
end
