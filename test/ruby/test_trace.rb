require 'test/unit'

$KCODE = 'none'

class TestTrace < Test::Unit::TestCase
  def test_trace
    $x = 1234
    $y = 0
    trace_var :$x, proc{$y = $x}
    $x = 40414
    assert($y == $x)
    
    untrace_var :$x
    $x = 19660208
    assert($y != $x)
    
    trace_var :$x, proc{$x *= 2}
    $x = 5
    assert($x == 10)
    
    untrace_var :$x
  end 
end
