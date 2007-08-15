require 'test/unit'

class TestProc < Test::Unit::TestCase
  def test_proc
    p1 = proc{|i| i}
    assert_equal(2, p1.call(2))
    assert_equal(3, p1.call(3))

    p1 = proc{|i| i*2}
    assert_equal(4, p1.call(2))
    assert_equal(6, p1.call(3))

    p2 = nil
    x=0

    proc{
      iii=5				# nested local variable
      p1 = proc{|i|
        iii = i
      }
      p2 = proc {
        x = iii                 	# nested variables shared by procs
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
    p1.call(5)
    p2.call
    assert_equal(5, x)
  end

  def assert_arity(n)
    meta = class << self; self; end
    meta.class_eval {define_method(:foo, Proc.new)}
    assert_equal(n, method(:foo).arity)
  end

  def test_arity
    assert_equal(-1, proc{}.arity)
    assert_equal(0, proc{||}.arity)
    assert_equal(1, proc{|x|}.arity)
    assert_equal(2, proc{|x, y|}.arity)
    assert_equal(-2, proc{|x, *y|}.arity)
    assert_equal(-1, proc{|*x|}.arity)
    assert_equal(-1, proc{|*|}.arity)

    assert_arity(-1) {}
    assert_arity(0) {||}
    assert_arity(1) {|x|}
    assert_arity(2) {|x, y|}
    assert_arity(-2) {|x, *y|}
    assert_arity(-1) {|*x|}
    assert_arity(-1) {|*|}
  end

  # [ruby-dev:22592]
  def m(x)
    lambda { x }
  end
  def test_eq
    # [ruby-dev:22592]
    a = m(1)
    b = m(2)
    assert_not_equal(a, b)
    assert_not_equal(a.call, b.call)

    # [ruby-dev:22599]
    assert_not_equal(proc {||}, proc {|x,y|})

    # [ruby-dev:22601]
    a = lambda {|x| lambda {} }.call(1)
    b = lambda {}
    assert_not_equal(a, b)
  end
end
