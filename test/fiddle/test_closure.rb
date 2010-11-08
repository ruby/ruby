require_relative 'helper'

module Fiddle
  class TestClosure < Fiddle::TestCase
    def test_argument_errors
      assert_raises(TypeError) do
        Closure.new(TYPE_INT, TYPE_INT)
      end

      assert_raises(TypeError) do
        Closure.new('foo', [TYPE_INT])
      end

      assert_raises(TypeError) do
        Closure.new(TYPE_INT, ['meow!'])
      end
    end

    def test_call
      closure = Class.new(Closure) {
        def call
          10
        end
      }.new(TYPE_INT, [])

      func = Function.new(closure, [], TYPE_INT)
      assert_equal 10, func.call
    end

    def test_returner
      closure = Class.new(Closure) {
        def call thing
          thing
        end
      }.new(TYPE_INT, [TYPE_INT])

      func = Function.new(closure, [TYPE_INT], TYPE_INT)
      assert_equal 10, func.call(10)
    end

    def test_block_caller
      cb = Closure::BlockCaller.new(TYPE_INT, [TYPE_INT]) do |one|
        one
      end
      func = Function.new(cb, [TYPE_INT], TYPE_INT)
      assert_equal 11, func.call(11)
    end

    def test_memsize
      require 'objspace'
      bug = '[ruby-dev:42480]'
      n = 10000
      assert_equal(n, n.times {ObjectSpace.memsize_of(Closure.allocate)}, bug)
    end
  end
end
