# frozen_string_literal: true
require_relative "helper"
require "rubygems/deprecate"

class TestDeprecate < Gem::TestCase
  def setup
    super

    @original_skip = Gem::Deprecate.skip
    Gem::Deprecate.skip = false
  end

  def teardown
    super

    Gem::Deprecate.skip = @original_skip
  end

  def test_defaults
    assert_equal false, @original_skip
  end

  def test_assignment
    Gem::Deprecate.skip = false
    assert_equal false, Gem::Deprecate.skip

    Gem::Deprecate.skip = true
    assert_equal true, Gem::Deprecate.skip

    Gem::Deprecate.skip = nil
    assert([true,false].include?(Gem::Deprecate.skip))
  end

  def test_skip
    Gem::Deprecate.skip_during do
      assert_equal true, Gem::Deprecate.skip
    end

    Gem::Deprecate.skip = nil
  end

  class Thing
    extend Gem::Deprecate
    attr_accessor :message
    def foo
      @message = "foo"
    end

    def bar
      @message = "bar"
    end
    rubygems_deprecate :foo, :bar

    def foo_arg(msg)
      @message = "foo" + msg
    end

    def bar_arg(msg)
      @message = "bar" + msg
    end
    rubygems_deprecate :foo_arg, :bar_arg

    def foo_kwarg(message:)
      @message = "foo" + message
    end

    def bar_kwarg(message:)
      @message = "bar" + message
    end
    rubygems_deprecate :foo_kwarg, :bar_kwarg
  end

  class OtherThing
    extend Gem::Deprecate
    attr_accessor :message
    def foo
      @message = "foo"
    end

    def bar
      @message = "bar"
    end
    deprecate :foo, :bar, 2099, 3

    def foo_arg(msg)
      @message = "foo" + msg
    end

    def bar_arg(msg)
      @message = "bar" + msg
    end
    deprecate :foo_arg, :bar_arg, 2099, 3

    def foo_kwarg(message:)
      @message = "foo" + message
    end

    def bar_kwarg(message:)
      @message = "bar" + message
    end
    deprecate :foo_kwarg, :bar_kwarg, 2099, 3
  end

  def test_deprecated_method_calls_the_old_method
    capture_output do
      thing = Thing.new
      thing.foo
      assert_equal "foo", thing.message
      thing.foo_arg("msg")
      assert_equal "foomsg", thing.message
      thing.foo_kwarg(message: "msg")
      assert_equal "foomsg", thing.message
    end
  end

  def test_deprecated_method_outputs_a_warning
    out, err = capture_output do
      thing = Thing.new
      thing.foo
      thing.foo_arg("msg")
      thing.foo_kwarg(message: "msg")
    end

    assert_equal "", out
    assert_match(/Thing#foo is deprecated; use bar instead\./, err)
    assert_match(/Thing#foo_arg is deprecated; use bar_arg instead\./, err)
    assert_match(/Thing#foo_kwarg is deprecated; use bar_kwarg instead\./, err)
    assert_match(/in Rubygems [0-9]+/, err)
  end

  def test_rubygems_deprecate_command
    require "rubygems/command"
    foo_command = Class.new(Gem::Command) do
      extend Gem::Deprecate

      rubygems_deprecate_command

      def execute
        puts "pew pew!"
      end
    end

    Gem::Commands.send(:const_set, :FooCommand, foo_command)
    assert Gem::Commands::FooCommand.new("foo").deprecated?
  ensure
    Gem::Commands.send(:remove_const, :FooCommand)
  end

  def test_deprecated_method_outputs_a_warning_old_way
    out, err = capture_output do
      thing = OtherThing.new
      thing.foo
      thing.foo_arg("msg")
      thing.foo_kwarg(message: "msg")
    end

    assert_equal "", out
    assert_match(/OtherThing#foo is deprecated; use bar instead\./, err)
    assert_match(/OtherThing#foo_arg is deprecated; use bar_arg instead\./, err)
    assert_match(/OtherThing#foo_kwarg is deprecated; use bar_kwarg instead\./, err)
    assert_match(/on or after 2099-03/, err)
  end
end
