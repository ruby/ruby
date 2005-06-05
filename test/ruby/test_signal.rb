require 'test/unit'
require 'timeout'

class TestSignal < Test::Unit::TestCase
  def test_signal
    defined?(Process.kill) or return
    begin
      $x = 0
      oldtrap = trap "SIGINT", proc{|sig| $x = 2}
      Process.kill "SIGINT", $$
      sleep 0.1
      assert_equal(2, $x)

      trap "SIGINT", proc{raise "Interrupt"}

      x = assert_raises(RuntimeError) do
        Process.kill "SIGINT", $$
        sleep 0.1
      end
      assert(x)
      assert_match(/Interrupt/, x.message)
    ensure
      trap "SIGINT", oldtrap
    end
  end

  def test_exit_action
    begin
      r, w = IO.pipe
      pid = fork {
        r0, w0 = IO.pipe
        trap(:USR1, "EXIT")
        Thread.start { Thread.pass }
        r0.sysread(4096)
      }
      sleep 0.1
      assert_nothing_raised("[ruby-dev:26128]") {
        Process.kill(:USR1, pid)
        begin
          Timeout.timeout(1) {
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
    end
  end
end
