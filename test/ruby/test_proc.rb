require 'test/unit'

$KCODE = 'none'

class TestProc < Test::Unit::TestCase
  def test_proc
    $proc = proc{|i| i}
    assert_equal($proc.call(2), 2)
    assert_equal($proc.call(3), 3)
    
    $proc = proc{|i| i*2}
    assert_equal($proc.call(2), 4)
    assert_equal($proc.call(3), 6)
    
    proc{
      iii=5				# nested local variable
      $proc = proc{|i|
        iii = i
      }
      $proc2 = proc {
        $x = iii			# nested variables shared by procs
      }
      # scope of nested variables
      assert(defined?(iii))
    }.call
    assert(!defined?(iii))		# out of scope
    
    loop{iii=5; assert(eval("defined? iii")); break}
    loop {
      iii = 10
      def dyna_var_check
        loop {
          assert(!defined?(iii))
          break
        }
      end
      dyna_var_check
      break
    }
    $x=0
    $proc.call(5)
    $proc2.call
    assert_equal($x, 5)
  end
end
