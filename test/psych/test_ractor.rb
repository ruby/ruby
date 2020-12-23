# frozen_string_literal: true
require_relative 'helper'

class TestPsychRactor < Test::Unit::TestCase
  def test_ractor_round_trip
    assert_ractor(<<~RUBY, require_relative: 'helper')
      obj = {foo: [42]}
      obj2 = Ractor.new(obj) do |obj|
        Psych.load(Psych.dump(obj))
      end.take
      assert_equal obj, obj2
    RUBY
  end

  def test_not_shareable
    # There's no point in making these frozen / shareable
    # and the C-ext disregards begin frozen
    assert_ractor(<<~RUBY, require_relative: 'helper')
      parser = Psych::Parser.new
      emitter = Psych::Emitter.new(nil)
      assert_raise(Ractor::Error) { Ractor.make_shareable(parser) }
      assert_raise(Ractor::Error) { Ractor.make_shareable(emitter) }
    RUBY
  end

  def test_ractor_config
    # Config is ractor-local
    # Test is to make sure it works, even though usage is probably very low.
    # The methods are not documented and might be deprecated one day
    assert_ractor(<<~RUBY, require_relative: 'helper')
      r = Ractor.new do
        Psych.add_builtin_type 'omap' do |type, val|
          val * 2
        end
        Psych.load('--- !!omap hello')
      end.take
      assert_equal 'hellohello', r
      assert_equal 'hello', Psych.load('--- !!omap hello')
    RUBY
  end

  def test_ractor_constants
    assert_ractor(<<~RUBY, require_relative: 'helper')
      r = Ractor.new do
        Psych.libyaml_version.join('.') == Psych::LIBYAML_VERSION
      end.take
      assert_equal true, r
    RUBY
  end
end if defined?(Test::Unit::TestCase)
