require 'test/unit'

$KCODE = 'none'

class TestEval < Test::Unit::TestCase
  # eval with binding
  def test_ev
    local1 = "local1"
    lambda {
      local2 = "local2"
      return binding
    }.call
  end

  def test_eval
    assert(eval("") == nil)
    $bad=false
    eval 'while false; $bad = true; print "foo\n" end'
    assert(!$bad)
    
    assert(eval('TRUE'))
    assert(eval('true'))
    assert(!eval('NIL'))
    assert(!eval('nil'))
    assert(!eval('FALSE'))
    assert(!eval('false'))
    
    $foo = 'assert(true)'
    begin
      eval $foo
    rescue
      assert(false)
    end
    
    assert(eval("$foo") == 'assert(true)')
    assert(eval("true") == true)
    i = 5
    assert(eval("i == 5"))
    assert(eval("i") == 5)
    assert(eval("defined? i"))
    
    $x = test_ev
    assert(eval("local1", $x) == "local1") # normal local var
    assert(eval("local2", $x) == "local2") # nested local var
    $bad = true
    begin
      p eval("local1")
    rescue NameError		# must raise error
      $bad = false
    end
    assert(!$bad)
    
    # !! use class_eval to avoid nested definition
    self.class.class_eval %q(
      module EvTest
	EVTEST1 = 25
	evtest2 = 125
	$x = binding
      end
    )
    assert(eval("EVTEST1", $x) == 25)	# constant in module
    assert(eval("evtest2", $x) == 125)	# local var in module
    $bad = true
    begin
      eval("EVTEST1")
    rescue NameError		# must raise error
      $bad = false
    end
    assert(!$bad)
    
    x = proc{}
    eval "i4 = 1", x
    assert(eval("i4", x) == 1)
    x = proc{proc{}}.call
    eval "i4 = 22", x
    assert(eval("i4", x) == 22)
    $x = []
    x = proc{proc{}}.call
    eval "(0..9).each{|i5| $x[i5] = proc{i5*2}}", x
    assert($x[4].call == 8)
    
    x = binding
    eval "i = 1", x
    assert(eval("i", x) == 1)
    x = proc{binding}.call
    eval "i = 22", x
    assert(eval("i", x) == 22)
    $x = []
    x = proc{binding}.call
    eval "(0..9).each{|i5| $x[i5] = proc{i5*2}}", x
    assert($x[4].call == 8)
    x = proc{binding}.call
    eval "for i6 in 1..1; j6=i6; end", x
    assert(eval("defined? i6", x))
    assert(eval("defined? j6", x))
    
    proc {
      p = binding
      eval "foo11 = 1", p
      foo22 = 5
      proc{foo11=22}.call
      proc{foo22=55}.call
      assert(eval("foo11", p) == eval("foo11"))
      assert(eval("foo11") == 1)
      assert(eval("foo22", p) == eval("foo22"))
      assert(eval("foo22") == 55)
    }.call
    
    p1 = proc{i7 = 0; proc{i7}}.call
    assert(p1.call == 0)
    eval "i7=5", p1
    assert(p1.call == 5)
    assert(!defined?(i7))
    
    p1 = proc{i7 = 0; proc{i7}}.call
    i7 = nil
    assert(p1.call == 0)
    eval "i7=1", p1
    assert(p1.call == 1)
    eval "i7=5", p1
    assert(p1.call == 5)
    assert(i7 == nil)
  end
end
