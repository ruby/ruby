# frozen_string_literal: true
begin
  require_relative 'helper'
rescue LoadError
end

module Fiddle
  class TestClosure < Fiddle::TestCase
    def teardown
      super
      # Ensure freeing all closures.
      # See https://github.com/ruby/fiddle/issues/102#issuecomment-1241763091 .
      not_freed_closures = []
      ObjectSpace.each_object(Fiddle::Closure) do |closure|
        not_freed_closures << closure unless closure.freed?
      end
      assert_equal([], not_freed_closures)
    end

    def test_argument_errors
      assert_raise(TypeError) do
        Closure.new(TYPE_INT, TYPE_INT)
      end

      assert_raise(TypeError) do
        Closure.new('foo', [TYPE_INT])
      end

      assert_raise(TypeError) do
        Closure.new(TYPE_INT, ['meow!'])
      end
    end

    def test_type_symbol
      Closure.create(:int, [:void]) do |closure|
        assert_equal([
                       TYPE_INT,
                       [TYPE_VOID],
                     ],
                     [
                       closure.instance_variable_get(:@ctype),
                       closure.instance_variable_get(:@args),
                     ])
      end
    end

    def test_call
      closure_class = Class.new(Closure) do
        def call
          10
        end
      end
      closure_class.create(TYPE_INT, []) do |closure|
        func = Function.new(closure, [], TYPE_INT)
        assert_equal 10, func.call
      end
    end

    def test_returner
      closure_class = Class.new(Closure) do
        def call thing
          thing
        end
      end
      closure_class.create(TYPE_INT, [TYPE_INT]) do |closure|
        func = Function.new(closure, [TYPE_INT], TYPE_INT)
        assert_equal 10, func.call(10)
      end
    end

    def test_const_string
      closure_class = Class.new(Closure) do
        def call(string)
          @return_string = "Hello! #{string}"
          @return_string
        end
      end
      closure_class.create(:const_string, [:const_string]) do |closure|
        func = Function.new(closure, [:const_string], :const_string)
        assert_equal("Hello! World!", func.call("World!"))
      end
    end

    def test_free
      Closure.create(:int, [:void]) do |closure|
        assert(!closure.freed?)
        closure.free
        assert(closure.freed?)
        closure.free
      end
    end

    def test_block_caller
      cb = Closure::BlockCaller.new(TYPE_INT, [TYPE_INT]) do |one|
        one
      end
      begin
        func = Function.new(cb, [TYPE_INT], TYPE_INT)
        assert_equal 11, func.call(11)
      ensure
        cb.free
      end
    end

    def test_memsize_ruby_dev_42480
      require 'objspace'
      n = 10000
      n.times do
        Closure.create(:int, [:void]) do |closure|
          ObjectSpace.memsize_of(closure)
        end
      end
    end

    %w[INT SHORT CHAR LONG LONG_LONG].each do |name|
      type = Fiddle.const_get("TYPE_#{name}") rescue next
      size = Fiddle.const_get("SIZEOF_#{name}")
      [[type, size-1, name], [-type, size, "unsigned_"+name]].each do |t, s, n|
        define_method("test_conversion_#{n.downcase}") do
          arg = nil

          closure_class = Class.new(Closure) do
            define_method(:call) {|x| arg = x}
          end
          closure_class.create(t, [t]) do |closure|
            v = ~(~0 << (8*s))

            arg = nil
            assert_equal(v, closure.call(v))
            assert_equal(arg, v, n)

            arg = nil
            func = Function.new(closure, [t], t)
            assert_equal(v, func.call(v))
            assert_equal(arg, v, n)
          end
        end
      end
    end
  end
end if defined?(Fiddle)
