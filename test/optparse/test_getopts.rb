# frozen_string_literal: false
require 'test/unit'
require 'optparse'

class TestOptionParserGetopts < Test::Unit::TestCase
  def setup
    @opt = OptionParser.new
  end

  def test_short_noarg
    o = @opt.getopts(%w[-a], "ab")
    assert_equal(true, o['a'])
    assert_equal(false, o['b'])

    o = @opt.getopts(%w[-a], "ab", symbolize_names: true)
    assert_equal(true, o[:a])
    assert_equal(false, o[:b])
  end

  def test_short_arg
    o = @opt.getopts(%w[-a1], "a:b:")
    assert_equal("1", o['a'])
    assert_equal(nil, o['b'])

    o = @opt.getopts(%w[-a1], "a:b:", symbolize_names: true)
    assert_equal("1", o[:a])
    assert_equal(nil, o[:b])
  end

  def test_long_noarg
    o = @opt.getopts(%w[--foo], "", "foo", "bar")
    assert_equal(true, o['foo'])
    assert_equal(false, o['bar'])

    o = @opt.getopts(%w[--foo], "", "foo", "bar", symbolize_names: true)
    assert_equal(true, o[:foo])
    assert_equal(false, o[:bar])
  end

  def test_long_arg
    o = @opt.getopts(%w[--bar ZOT], "", "foo:FOO", "bar:BAR")
    assert_equal("FOO", o['foo'])
    assert_equal("ZOT", o['bar'])

    o = @opt.getopts(%w[--bar ZOT], "", "foo:FOO", "bar:BAR", symbolize_names: true)
    assert_equal("FOO", o[:foo])
    assert_equal("ZOT", o[:bar])
  end
end
