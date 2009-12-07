require 'test/unit'
require 'delegate'

class TestDelegateClass < Test::Unit::TestCase
  module M
    attr_reader :m
  end

  def test_extend
    obj = DelegateClass(Array).new([])
    obj.instance_eval { @m = :m }
    obj.extend M
    assert_equal(:m, obj.m, "[ruby-dev:33116]")
  end

  def test_systemcallerror_eq
    e = SystemCallError.new(0)
    assert((SimpleDelegator.new(e) == e) == (e == SimpleDelegator.new(e)), "[ruby-dev:34808]")
  end

  class Myclass < DelegateClass(Array);end

  def test_delegateclass_class
    myclass=Myclass.new([])
    assert_equal(Myclass,myclass.class)
  end

  def test_simpledelegator_class
    simple=SimpleDelegator.new([])
    assert_equal(SimpleDelegator,simple.class)
  end

  class Object
    def m
      :o
    end
  end

  class Foo
    def m
      :m
    end
  end

  class Bar < DelegateClass(Foo)
  end

  def test_override
    assert_equal(:o, Object.new.m)
    assert_equal(:m, Foo.new.m)
    assert_equal(:m, SimpleDelegator.new(Foo.new).m)
    assert_equal(:m, Bar.new(Foo.new).m)
  end

  class IV < DelegateClass(Integer)
    attr_accessor :var

    def initialize
      @var = 1
    end
  end

  def test_marshal
    bug1744 = '[ruby-core:24211]'
    c = IV.new
    assert_equal(1, c.var)
    d = Marshal.load(Marshal.dump(c))
    assert_equal(1, d.var, bug1744)
  end
end
