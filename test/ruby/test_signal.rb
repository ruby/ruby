require 'test/unit'

$KCODE = 'none'

class TestSignal < Test::Unit::TestCase
  def test_signal
    if defined? Process.kill
      $x = 0
      trap "SIGINT", proc{|sig| $x = 2}
      Process.kill "SIGINT", $$
      sleep 0.1
      assert_equal($x, 2)
    
      trap "SIGINT", proc{raise "Interrupt"}
    
      x = false
      begin
        Process.kill "SIGINT", $$
        sleep 0.1
      rescue
        x = $!
      end
      assert(x && /Interrupt/ =~ x.message)
    end
  end
end
