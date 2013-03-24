require 'test/unit'
require_relative 'envutil'

class TestSuper < Test::Unit::TestCase
  class Base
    def single(a) a end
    def double(a, b) [a,b] end
    def array(*a) a end
    def optional(a = 0) a end
    def keyword(**a) a end
  end
  class Single1 < Base
    def single(*) super end
  end
  class Single2 < Base
    def single(a,*) super end
  end
  class Double1 < Base
    def double(*) super end
  end
  class Double2 < Base
    def double(a,*) super end
  end
  class Double3 < Base
    def double(a,b,*) super end
  end
  class Array1 < Base
    def array(*) super end
  end
  class Array2 < Base
    def array(a,*) super end
  end
  class Array3 < Base
    def array(a,b,*) super end
  end
  class Array4 < Base
    def array(a,b,c,*) super end
  end
  class Optional1 < Base
    def optional(a = 1) super end
  end
  class Optional2 < Base
    def optional(a, b = 1) super end
  end
  class Optional3 < Base
    def single(a = 1) super end
  end
  class Optional4 < Base
    def array(a = 1, *) super end
  end
  class Optional5 < Base
    def array(a = 1, b = 2, *) super end
  end
  class Keyword1 < Base
    def keyword(foo: "keyword1") super end
  end
  class Keyword2 < Base
    def keyword(foo: "keyword2")
      foo = "changed1"
      x = super
      foo = "changed2"
      y = super
      [x, y]
    end
  end

  def test_single1
    assert_equal(1, Single1.new.single(1))
  end
  def test_single2
    assert_equal(1, Single2.new.single(1))
  end
  def test_double1
    assert_equal([1, 2], Double1.new.double(1, 2))
  end
  def test_double2
    assert_equal([1, 2], Double2.new.double(1, 2))
  end
  def test_double3
    assert_equal([1, 2], Double3.new.double(1, 2))
  end
  def test_array1
    assert_equal([], Array1.new.array())
    assert_equal([1], Array1.new.array(1))
  end
  def test_array2
    assert_equal([1], Array2.new.array(1))
    assert_equal([1,2], Array2.new.array(1, 2))
  end
  def test_array3
    assert_equal([1,2], Array3.new.array(1, 2))
    assert_equal([1,2,3], Array3.new.array(1, 2, 3))
  end
  def test_array4
    assert_equal([1,2,3], Array4.new.array(1, 2, 3))
    assert_equal([1,2,3,4], Array4.new.array(1, 2, 3, 4))
  end
  def test_optional1
    assert_equal(9, Optional1.new.optional(9))
    assert_equal(1, Optional1.new.optional)
  end
  def test_optional2
    assert_raise(ArgumentError) do
      # call Base#optional with 2 arguments; the 2nd arg is supplied
      assert_equal(9, Optional2.new.optional(9))
    end
    assert_raise(ArgumentError) do
      # call Base#optional with 2 arguments
      assert_equal(9, Optional2.new.optional(9, 2))
    end
  end
  def test_optional3
    assert_equal(9, Optional3.new.single(9))
    # call Base#single with 1 argument; the arg is supplied
    assert_equal(1, Optional3.new.single)
  end
  def test_optional4
    assert_equal([1], Optional4.new.array)
    assert_equal([9], Optional4.new.array(9))
    assert_equal([9, 8], Optional4.new.array(9, 8))
  end
  def test_optional5
    assert_equal([1, 2], Optional5.new.array)
    assert_equal([9, 2], Optional5.new.array(9))
    assert_equal([9, 8], Optional5.new.array(9, 8))
    assert_equal([9, 8, 7], Optional5.new.array(9, 8, 7))
  end
  def test_keyword1
    assert_equal({foo: "keyword1"}, Keyword1.new.keyword)
    bug8008 = '[ruby-core:53114] [Bug #8008]'
    assert_equal({foo: bug8008}, Keyword1.new.keyword(foo: bug8008))
  end
  def test_keyword2
    assert_equal([{foo: "changed1"}, {foo: "changed2"}], Keyword2.new.keyword)
  end

  class A
    def tt(aa)
      "A#tt"
    end

    def uu(a)
      class << self
        define_method(:tt) do |sym|
          super(sym)
        end
      end
    end
  end

  def test_define_method
    a = A.new
    a.uu(12)
    assert_equal("A#tt", a.tt(12), "[ruby-core:3856]")
    e = assert_raise(RuntimeError, "[ruby-core:24244]") {
      lambda {
        Class.new {
          define_method(:a) {super}
        }.new.a
      }.call
    }
    assert_match(/implicit argument passing of super from method defined by define_method/, e.message)
  end

  class SubSeq
    def initialize
      @first=11
      @first or fail
    end

    def subseq
      @first or fail
    end
  end

  class Indexed
    def subseq
      SubSeq.new
    end
  end

  Overlaid = proc do
    class << self
      def subseq
        super.instance_eval(& Overlaid)
      end
    end
  end

  def test_overlaid
    assert_nothing_raised('[ruby-dev:40959]') do
      overlaid = proc do |obj|
        def obj.reverse
          super
        end
      end
      overlaid.call(str = "123")
      overlaid.call(ary = [1,2,3])
      str.reverse
    end

    assert_nothing_raised('[ruby-core:27230]') do
      mid=Indexed.new
      mid.instance_eval(&Overlaid)
      mid.subseq
      mid.subseq
    end
  end

  module DoubleInclude
    class Base
      def foo
        [:Base]
      end
    end

    module Override
      def foo
        super << :Override
      end
    end

    class A < Base
    end

    class B < A
    end

    B.send(:include, Override)
    A.send(:include, Override)
  end

  # [Bug #3351]
  def test_double_include
    assert_equal([:Base, :Override], DoubleInclude::B.new.foo)
    # should be changed as follows?
    # assert_equal([:Base, :Override, :Override], DoubleInclude::B.new.foo)
  end

  module DoubleInclude2
    class Base
      def foo
        [:Base]
      end
    end

    module Override
      def foo
        super << :Override
      end
    end

    class A < Base
      def foo
        super << :A
      end
    end

    class B < A
      def foo
        super << :B
      end
    end

    B.send(:include, Override)
    A.send(:include, Override)
  end

  def test_double_include2
    assert_equal([:Base, :Override, :A, :Override, :B],
                 DoubleInclude2::B.new.foo)
  end

  def test_super_in_instance_eval
    super_class = Class.new {
      def foo
        return [:super, self]
      end
    }
    sub_class = Class.new(super_class) {
      def foo
        x = Object.new
        x.instance_eval do
          super()
        end
      end
    }
    obj = sub_class.new
    assert_raise(TypeError) do
      obj.foo
    end
  end

  def test_super_in_instance_eval_with_define_method
    super_class = Class.new {
      def foo
        return [:super, self]
      end
    }
    sub_class = Class.new(super_class) {
      define_method(:foo) do
        x = Object.new
        x.instance_eval do
          super()
        end
      end
    }
    obj = sub_class.new
    assert_raise(TypeError) do
      obj.foo
    end
  end

  def test_super_in_orphan_block
    super_class = Class.new {
      def foo
        return [:super, self]
      end
    }
    sub_class = Class.new(super_class) {
      def foo
        x = Object.new
        lambda { super() }
      end
    }
    obj = sub_class.new
    assert_equal([:super, obj], obj.foo.call)
  end

  def test_super_in_orphan_block_with_instance_eval
    super_class = Class.new {
      def foo
        return [:super, self]
      end
    }
    sub_class = Class.new(super_class) {
      def foo
        x = Object.new
        x.instance_eval do
          lambda { super() }
        end
      end
    }
    obj = sub_class.new
    assert_raise(TypeError) do
      obj.foo.call
    end
  end

  def test_yielding_super
    a = Class.new { def yielder; yield; end }
    x = Class.new { define_singleton_method(:hello) { 'hi' } }
    y = Class.new(x) {
      define_singleton_method(:hello) {
        m = a.new
        m.yielder { super() }
      }
    }
    assert_equal 'hi', y.hello
  end

  def test_super_in_thread
    hoge = Class.new {
      def bar; 'hoge'; end
    }
    foo = Class.new(hoge) {
      def bar; Thread.new { super }.join.value; end
    }

    assert_equal 'hoge', foo.new.bar
  end

  def assert_super_in_block(type)
    bug7064 = '[ruby-core:47680]'
    assert_normal_exit "#{type} {super}", bug7064
  end

  def test_super_in_at_exit
    assert_super_in_block("at_exit")
  end
  def test_super_in_END
    assert_super_in_block("END")
  end

  def test_super_in_BEGIN
    assert_super_in_block("BEGIN")
  end
end
