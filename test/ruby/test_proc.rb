require 'test/unit'

$KCODE = 'none'

class TestProc < Test::Unit::TestCase
  def test_proc
    $proc = proc{|i| i}
    assert_equal(2, $proc.call(2))
    assert_equal(3, $proc.call(3))

    $proc = proc{|i| i*2}
    assert_equal(4, $proc.call(2))
    assert_equal(6, $proc.call(3))

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
      def self.dyna_var_check
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
    assert_equal(5, $x)
  end
end
