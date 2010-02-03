require_relative 'test_base'
require 'dl/func'
require 'dl/closure'

module DL
  class TestClosure < Test::Unit::TestCase
    class Returner < DL::Closure
      attr_accessor :called
      attr_accessor :called_with
      def call *args
        @called = true
        @called_with = args
        a = args.first
        DL::CPtr === a ? a.to_i : a
      end
    end

    if defined?(TYPE_LONG_LONG)
      def test_long_long
        type = TYPE_LONG_LONG
        addr = Returner.new(type, [type]) do |num|
          called = true
          called_with = num
        end
        func = DL::Function.new(addr, [type])
        assert_equal(9223372036854775807, func.call(9223372036854775807))
      end
    end

    def test_with_abi
      called = false
      addr = DL::Closure::BlockCaller.new(
          TYPE_INT,
          [TYPE_INT],
          DL::Function::DEFAULT
      ) do |num|
        called = true
	num
      end
      func = DL::Function.new(addr, [TYPE_INT])
      func.call(50)
      assert called
    end

    def test_block_caller
      called = false
      called_with = nil
      addr = DL::Closure::BlockCaller.new(TYPE_INT, [TYPE_INT]) do |num|
        called = true
        called_with = num
      end
      func = DL::Function.new(addr, [TYPE_INT])
      func.call(50)
      assert called, 'function was called'
      assert_equal 50, called_with
    end

    def test_multival
      adder = Class.new(DL::Closure) {
        def call a, b
          a + b
        end
      }.new(TYPE_INT, [TYPE_INT, TYPE_INT])

      assert_equal [TYPE_INT, TYPE_INT], adder.args
      func = DL::Function.new(adder, adder.args)
      assert_equal 70, func.call(50, 20)
    end

    def test_call
      closure = Class.new(DL::Closure) {
        attr_accessor :called_with
        def call num
          @called_with = num
        end
      }.new(TYPE_INT, [TYPE_INT])

      func = DL::Function.new(closure, [TYPE_INT])
      func.call(50)

      assert_equal 50, closure.called_with
    end

    def test_return_value
      closure = Returner.new(TYPE_INT, [TYPE_INT])

      func = DL::Function.new(closure, [TYPE_INT])
      assert_equal 50, func.call(50)
    end

    def test_float
      closure = Returner.new(TYPE_FLOAT, [TYPE_FLOAT])
      func = DL::Function.new(closure, [TYPE_FLOAT])
      assert_equal 2.0, func.call(2.0)
    end

    def test_char
      closure = Returner.new(TYPE_CHAR, [TYPE_CHAR])
      func = DL::Function.new(closure, [TYPE_CHAR])
      assert_equal 60, func.call(60)
    end

    def test_long
      closure = Returner.new(TYPE_LONG, [TYPE_LONG])
      func = DL::Function.new(closure, [TYPE_LONG])
      assert_equal 60, func.call(60)
    end

    def test_double
      closure = Returner.new(TYPE_DOUBLE, [TYPE_DOUBLE])
      func = DL::Function.new(closure, [TYPE_DOUBLE])
      assert_equal 60, func.call(60)
    end

    def test_voidp
      closure = Returner.new(TYPE_VOIDP, [TYPE_VOIDP])
      func = DL::Function.new(closure, [TYPE_VOIDP])

      voidp = CPtr['foo']
      assert_equal voidp, func.call(voidp)
    end

    def test_void
      closure = Returner.new(TYPE_VOID, [TYPE_VOID])
      func = DL::Function.new(closure, [TYPE_VOID])
      func.call()
      assert closure.called
    end
  end
end
