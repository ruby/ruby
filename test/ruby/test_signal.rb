require 'test/unit'

$KCODE = 'none'

class TestSignal < Test::Unit::TestCase
  def test_signal
    if defined? Process.kill
      $x = 0
      trap "SIGINT", proc{|sig| $x = 2}
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
    end
  end
end
