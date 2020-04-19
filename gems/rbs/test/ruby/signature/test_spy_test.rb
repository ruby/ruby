require "test_helper"

require "ruby/signature/test"
require "logger"

return unless Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('2.7.0')

class Ruby::Signature::TestSpyTest < Minitest::Test
  include TestHelper

  Test = Ruby::Signature::Test

  def test_singleton_spy
    klass = Class.new do
      def fib(n)
        case n
        when 0, 1
          1
        else
          fib(n-1) + fib(n-2)
        end
      end

      def raising(x, foo:)
        raise "x = #{x}"
      end

      def yielding(x)
        x.times do |i|
          yield i
        end

        :foo
      end

      def instance_evaling(&block)
        instance_eval(&block)
        30
      end
    end

    obj = klass.new
    def obj.fib; end
    def obj.instance_evaling; end
    def obj.raising; end
    def obj.yielding; end

    Test::Spy.singleton_method(obj, :fib) do |spy|
      trace = []
      spy.callback = -> (result) { trace << result }

      obj.fib(2)

      assert_equal(
        [
          Test::CallTrace.new(
            method_name: :fib,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [1],
                return_value: 1,
                exception: nil
              ),
            block_calls: [],
            block_given: false
          ),
          Test::CallTrace.new(
            method_name: :fib,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [0],
                return_value: 1,
                exception: nil
              ),
            block_calls: [],
            block_given: false
          ),
          Test::CallTrace.new(
            method_name: :fib,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [2],
                return_value: 2,
                exception: nil
              ),
            block_calls: [],
            block_given: false
          )
        ],
        trace
      )
    end

    Test::Spy.singleton_method(obj, :raising) do |spy|
      trace = []
      spy.callback = -> (result) { trace << result }

      exn = assert_raises RuntimeError do
        obj.raising(1, foo: :bar)
      end

      assert_equal(
        [
          Test::CallTrace.new(
            method_name: :raising,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [1, { foo: :bar }],
                return_value: nil,
                exception: exn
              ),
            block_calls: [],
            block_given: false
          ),
        ],
        trace
      )
    end

    Test::Spy.singleton_method(obj, :yielding) do |spy|
      trace = []
      spy.callback = -> (result) { trace << result }

      obj.yielding(2) { }

      assert_equal(
        [
          Test::CallTrace.new(
            method_name: :yielding,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [2],
                return_value: :foo,
                exception: nil
              ),
            block_calls: [
              Test::ArgumentsReturn.new(
                arguments: [0],
                return_value: nil,
                exception: nil
              ),
              Test::ArgumentsReturn.new(
                arguments: [1],
                return_value: nil,
                exception: nil
              ),
            ],
            block_given: true
          ),
        ],
        trace
      )
    end

    Test::Spy.singleton_method(obj, :yielding) do |spy|
      trace = []
      spy.callback = -> (result) { trace << result }

      exn = assert_raises RuntimeError do
        obj.yielding(2) {|i| raise "given #{i}" }
      end

      assert_equal(
        [
          Test::CallTrace.new(
            method_name: :yielding,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [2],
                return_value: nil,
                exception: exn
              ),
            block_calls: [
              Test::ArgumentsReturn.new(
                arguments: [0],
                return_value: nil,
                exception: exn
              )
            ],
            block_given: true
          ),
        ],
        trace
      )
    end

    Test::Spy.singleton_method(obj, :instance_evaling) do |spy|
      trace = []
      spy.callback = -> (result) { trace << result }

      obj.instance_evaling { self }

      assert_equal(
        [
          Test::CallTrace.new(
            method_name: :instance_evaling,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [],
                return_value: 30,
                exception: nil
              ),
            block_calls: [
              Test::ArgumentsReturn.new(
                arguments: [obj],
                return_value: obj,
                exception: nil
              )
            ],
            block_given: true
          ),
        ],
        trace
      )
    end
  end

  def test_instance_spy
    klass = Class.new do
      def fib(n)
        case n
        when 0, 1
          1
        else
          fib(n-1) + fib(n-2)
        end
      end

      def raising(x, foo:)
        raise "x = #{x}"
      end

      def yielding(x)
        x.times do |i|
          yield i
        end

        :foo
      end

      def instance_evaling(&block)
        instance_eval(&block)
        30
      end
    end

    Test::Spy.instance_method(klass, :fib) do |spy|
      trace = []
      spy.callback = -> (result) { trace << result }

      klass.new.fib(2)

      assert_equal(
        [
          Test::CallTrace.new(
            method_name: :fib,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [1],
                return_value: 1,
                exception: nil
              ),
            block_calls: [],
            block_given: false
          ),
          Test::CallTrace.new(
            method_name: :fib,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [0],
                return_value: 1,
                exception: nil
              ),
            block_calls: [],
            block_given: false
          ),
          Test::CallTrace.new(
            method_name: :fib,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [2],
                return_value: 2,
                exception: nil
              ),
            block_calls: [],
            block_given: false
          )
        ],
        trace
      )
    end

    Test::Spy.instance_method(klass, :raising) do |spy|
      trace = []
      spy.callback = -> (result) { trace << result }

      exn = assert_raises RuntimeError do
        klass.new.raising(1, foo: :bar)
      end

      assert_equal(
        [
          Test::CallTrace.new(
            method_name: :raising,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [1, { foo: :bar }],
                return_value: nil,
                exception: exn
              ),
            block_calls: [],
            block_given: false
          ),
        ],
        trace
      )
    end

    Test::Spy.instance_method(klass, :yielding) do |spy|
      trace = []
      spy.callback = -> (result) { trace << result }

      klass.new.yielding(2) { }

      assert_equal(
        [
          Test::CallTrace.new(
            method_name: :yielding,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [2],
                return_value: :foo,
                exception: nil
              ),
            block_calls: [
              Test::ArgumentsReturn.new(
                arguments: [0],
                return_value: nil,
                exception: nil
              ),
              Test::ArgumentsReturn.new(
                arguments: [1],
                return_value: nil,
                exception: nil
              ),
            ],
            block_given: true
          ),
        ],
        trace
      )
    end

    Test::Spy.instance_method(klass, :yielding) do |spy|
      trace = []
      spy.callback = -> (result) { trace << result }

      exn = assert_raises RuntimeError do
        klass.new.yielding(2) {|i| raise "given #{i}" }
      end

      assert_equal(
        [
          Test::CallTrace.new(
            method_name: :yielding,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [2],
                return_value: nil,
                exception: exn
              ),
            block_calls: [
              Test::ArgumentsReturn.new(
                arguments: [0],
                return_value: nil,
                exception: exn
              )
            ],
            block_given: true
          ),
        ],
        trace
      )
    end

    Test::Spy.instance_method(klass, :instance_evaling) do |spy|
      trace = []
      spy.callback = -> (result) { trace << result }

      obj = klass.new
      obj.instance_evaling { self }

      assert_equal(
        [
          Test::CallTrace.new(
            method_name: :instance_evaling,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [],
                return_value: 30,
                exception: nil
              ),
            block_calls: [
              Test::ArgumentsReturn.new(
                arguments: [obj],
                return_value: obj,
                exception: nil
              )
            ],
            block_given: true
          ),
        ],
        trace
      )
    end
  end

  def test_wrap_spy
    klass = Class.new do
      def fib(n)
        case n
        when 0, 1
          1
        else
          fib(n-1) + fib(n-2)
        end
      end

      def raising(x, foo:)
        raise "x = #{x}"
      end

      def yielding(x)
        x.times do |i|
          yield i
        end

        :foo
      end

      def instance_evaling(&block)
        instance_eval(&block)
        30
      end
    end

    Test::Spy.wrap(klass.new, :fib) do |spy, obj|
      trace = []
      spy.callback = -> (result) { trace << result }

      obj.fib(2)

      assert_equal(
        [
          Test::CallTrace.new(
            method_name: :fib,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [2],
                return_value: 2,
                exception: nil
              ),
            block_calls: [],
            block_given: false
          )
        ],
        trace
      )
    end

    Test::Spy.wrap(klass.new, :raising) do |spy, obj|
      trace = []
      spy.callback = -> (result) { trace << result }

      exn = assert_raises RuntimeError do
        obj.raising(1, foo: :bar)
      end

      assert_equal(
        [
          Test::CallTrace.new(
            method_name: :raising,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [1, { foo: :bar }],
                return_value: nil,
                exception: exn
              ),
            block_calls: [],
            block_given: false
          ),
        ],
        trace
      )
    end

    Test::Spy.wrap(klass.new, :raising) do |spy, obj|
      trace = []
      spy.callback = -> (result) { trace << result }

      exn = assert_raises ArgumentError do
        obj.raising()
      end

      assert_equal(
        [
          Test::CallTrace.new(
            method_name: :raising,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [],
                return_value: nil,
                exception: exn
              ),
            block_calls: [],
            block_given: false
          ),
        ],
        trace
      )
    end

    Test::Spy.wrap(klass.new, :yielding) do |spy, obj|
      trace = []
      spy.callback = -> (result) { trace << result }

      obj.yielding(2) { }

      assert_equal(
        [
          Test::CallTrace.new(
            method_name: :yielding,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [2],
                return_value: :foo,
                exception: nil
              ),
            block_calls: [
              Test::ArgumentsReturn.new(
                arguments: [0],
                return_value: nil,
                exception: nil
              ),
              Test::ArgumentsReturn.new(
                arguments: [1],
                return_value: nil,
                exception: nil
              ),
            ],
            block_given: true
          ),
        ],
        trace
      )
    end

    Test::Spy.wrap(klass.new, :yielding) do |spy, obj|
      trace = []
      spy.callback = -> (result) { trace << result }

      exn = assert_raises RuntimeError do
        obj.yielding(2) {|i| raise "given #{i}" }
      end

      assert_equal(
        [
          Test::CallTrace.new(
            method_name: :yielding,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [2],
                return_value: nil,
                exception: exn
              ),
            block_calls: [
              Test::ArgumentsReturn.new(
                arguments: [0],
                return_value: nil,
                exception: exn
              )
            ],
            block_given: true
          ),
        ],
        trace
      )
    end

    Test::Spy.wrap(klass.new, :instance_evaling) do |spy, obj|
      trace = []
      spy.callback = -> (result) { trace << result }

      obj.instance_evaling { self }

      assert_equal(
        [
          Test::CallTrace.new(
            method_name: :instance_evaling,
            method_call:
              Test::ArgumentsReturn.new(
                arguments: [],
                return_value: 30,
                exception: nil
              ),
            block_calls: [
              Test::ArgumentsReturn.new(
                arguments: [spy.object],
                return_value: spy.object,
                exception: nil
              )
            ],
            block_given: true
          ),
        ],
        trace
      )
    end
  end
end
