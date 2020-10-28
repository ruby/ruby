# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/deprecate'

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
    assert([true,false].include? Gem::Deprecate.skip)
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
  end

  def test_deprecated_method_calls_the_old_method
    capture_io do
      thing = Thing.new
      thing.foo
      assert_equal "foo", thing.message
    end
  end

  def test_deprecated_method_outputs_a_warning
    out, err = capture_io do
      thing = Thing.new
      thing.foo
    end

    assert_equal "", out
    assert_match(/Thing#foo is deprecated; use bar instead\./, err)
    assert_match(/in Rubygems [0-9]+/, err)
  end

  def test_rubygems_deprecate_command
    require 'rubygems/command'
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
    out, err = capture_io do
      thing = OtherThing.new
      thing.foo
    end

    assert_equal "", out
    assert_match(/Thing#foo is deprecated; use bar instead\./, err)
    assert_match(/on or after 2099-03-01/, err)
  end
end
