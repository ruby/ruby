begin
  require_relative 'helper'
rescue LoadError
end

module Fiddle
  class TestFunction < Fiddle::TestCase
    include Test::Unit::Assertions

    def setup
      super
      Fiddle.last_error = nil
    end

    def test_default_abi
      func = Function.new(@libm['sin'], [TYPE_DOUBLE], TYPE_DOUBLE)
      assert_equal Function::DEFAULT, func.abi
    end

    def test_name
      func = Function.new(@libm['sin'], [TYPE_DOUBLE], TYPE_DOUBLE, name: 'sin')
      assert_equal 'sin', func.name
    end

    def test_argument_errors
      assert_raises(TypeError) do
        Function.new(@libm['sin'], TYPE_DOUBLE, TYPE_DOUBLE)
      end

      assert_raises(TypeError) do
        Function.new(@libm['sin'], ['foo'], TYPE_DOUBLE)
      end

      assert_raises(TypeError) do
        Function.new(@libm['sin'], [TYPE_DOUBLE], 'foo')
      end
    end

    def test_call
      func = Function.new(@libm['sin'], [TYPE_DOUBLE], TYPE_DOUBLE)
      assert_in_delta 1.0, func.call(90 * Math::PI / 180), 0.0001
    end

    def test_argument_count
      closure = Class.new(Closure) {
        def call one
          10 + one
        end
      }.new(TYPE_INT, [TYPE_INT])
      func = Function.new(closure, [TYPE_INT], TYPE_INT)

      assert_raises(ArgumentError) do
        func.call(1,2,3)
      end
      assert_raises(ArgumentError) do
        func.call
      end
    end

    def test_last_error
      func = Function.new(@libc['strcpy'], [TYPE_VOIDP, TYPE_VOIDP], TYPE_VOIDP)

      assert_nil Fiddle.last_error
      func.call("000", "123")
      refute_nil Fiddle.last_error
    end

    def test_strcpy
      f = Function.new(@libc['strcpy'], [TYPE_VOIDP, TYPE_VOIDP], TYPE_VOIDP)
      buff = "000"
      str = f.call(buff, "123")
      assert_equal("123", buff)
      assert_equal("123", str.to_s)
    end

    def test_no_memory_leak
      prep = 'r = Fiddle::Function.new(Fiddle.dlopen(nil)["rb_obj_tainted"], [Fiddle::TYPE_UINTPTR_T], Fiddle::TYPE_UINTPTR_T); a = "a"'
      code = 'begin r.call(a); rescue TypeError; end'
      assert_no_memory_leak(%w[-W0 -rfiddle], "#{prep}\n1000.times{#{code}}", "10_000.times {#{code}}", limit: 1.2)
    end
  end
end if defined?(Fiddle)
