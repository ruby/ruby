# frozen_string_literal: false
require_relative 'test_optparse'

class TestOptionParserOptArg < TestOptionParser
  def setup
    super
    @opt.def_option("-x[VAL]") {|x| @flag = x}
    @opt.def_option("--option[=VAL]") {|x| @flag = x}
    @opt.def_option("--regexp[=REGEXP]", Regexp) {|x| @reopt = x}
    @opt.def_option "--with_underscore[=VAL]" do |x| @flag = x end
    @opt.def_option "--with-hyphen[=VAL]" do |x| @flag = x end
    @reopt = nil
  end

  def test_short
    assert_equal(%w"", no_error {@opt.parse!(%w"-x")})
    assert_equal(nil, @flag)
    @flag = false
    assert_equal(%w"foo", no_error {@opt.parse!(%w"-x foo")})
    assert_equal(nil, @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"-xfoo")})
    assert_equal("foo", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"-x=")})
    assert_equal("=", @flag)
  end

  def test_abbrev
    assert_equal(%w"", no_error {@opt.parse!(%w"-o")})
    assert_equal(nil, @flag)
    @flag = false
    assert_equal(%w"foo", no_error {@opt.parse!(%w"-o foo")})
    assert_equal(nil, @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"-ofoo")})
    assert_equal("foo", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"-o=")})
    assert_equal("=", @flag)
  end

  def test_long
    assert_equal(%w"", no_error {@opt.parse!(%w"--opt")})
    assert_equal(nil, @flag)
    assert_equal(%w"foo", no_error {@opt.parse!(%w"--opt= foo")})
    assert_equal("", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"--opt=foo")})
    assert_equal("foo", @flag)
    assert_equal(%w"foo", no_error {@opt.parse!(%w"--opt foo")})
    assert_equal(nil, @flag)
  end

  def test_hyphenize
    assert_equal(%w"", no_error {@opt.parse!(%w"--with_underscore=foo1")})
    assert_equal("foo1", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"--with-underscore=foo2")})
    assert_equal("foo2", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"--with-hyphen=foo3")})
    assert_equal("foo3", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"--with_hyphen=foo4")})
    assert_equal("foo4", @flag)
  end
end
