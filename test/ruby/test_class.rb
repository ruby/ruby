require 'test/unit'

class TestClass < Test::Unit::TestCase

  # ------------------
  # Various test classes
  # ------------------

  class ClassOne
    attr :num_args
    @@subs = []
    def initialize(*args)
      @num_args = args.size
      @args = args
    end
    def [](n)
      @args[n]
    end
    def ClassOne.inherited(klass)
      @@subs.push klass
    end
    def subs
      @@subs
    end
  end

  class ClassTwo < ClassOne
  end

  class ClassThree < ClassOne
  end

  class ClassFour < ClassThree
  end

  # ------------------
  # Start of tests
  # ------------------

  def test_s_inherited
    assert_equal([ClassTwo, ClassThree, ClassFour], ClassOne.new.subs)
  end

  def test_s_new
    c = Class.new
    assert_same(Class, c.class)
    assert_same(Object, c.superclass)

    c = Class.new(Fixnum)
    assert_same(Class, c.class)
    assert_same(Fixnum, c.superclass)
  end

  def test_00_new_basic
    a = ClassOne.new
    assert_equal(ClassOne, a.class)
    assert_equal(0, a.num_args)

    a = ClassOne.new(1, 2, 3)
    assert_equal(3, a.num_args)
    assert_equal(1, a[0])
  end

  def test_01_new_inherited
    a = ClassTwo.new
    assert_equal(ClassTwo, a.class)
    assert_equal(0, a.num_args)

    a = ClassTwo.new(1, 2, 3)
    assert_equal(3, a.num_args)
    assert_equal(1, a[0])
  end

  def test_superclass
    assert_equal(ClassOne, ClassTwo.superclass)
    assert_equal(Object,   ClassTwo.superclass.superclass)
    assert_equal(BasicObject, ClassTwo.superclass.superclass.superclass)
  end

  def test_class_cmp
    assert_raise(TypeError) { Class.new <= 1 }
    assert_raise(TypeError) { Class.new >= 1 }
    assert_nil(Class.new <=> 1)
  end

  def test_class_initialize
    assert_raise(TypeError) do
      Class.new.instance_eval { initialize }
    end
  end

  def test_instanciate_singleton_class
    c = class << Object.new; self; end
    assert_raise(TypeError) { c.new }
  end

  def test_superclass_of_basicobject
    assert_equal(nil, BasicObject.superclass)
  end

  def test_module_function
    c = Class.new
    assert_raise(TypeError) do
      Module.instance_method(:module_function).bind(c).call(:foo)
    end
  end

end
