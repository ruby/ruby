# frozen_string_literal: false
require_relative 'test_optparse'

class TestOptionParserPlaceArg < TestOptionParser
  def setup
    super
    @opt.def_option("-x [VAL]") {|x| @flag = x}
    @opt.def_option("--option [VAL]") {|x| @flag = x}
    @opt.def_option("-T [level]", /^[0-4]$/, Integer) {|x| @topt = x}
    @opt.def_option("--enum [VAL]", [:Alpha, :Bravo, :Charlie]) {|x| @enum = x}
    @opt.def_option("--enumval [VAL]", [[:Alpha, 1], [:Bravo, 2], [:Charlie, 3]]) {|x| @enum = x}
    @opt.def_option("--integer [VAL]", Integer, [1, 2, 3]) {|x| @integer = x}
    @opt.def_option("--range [VAL]", Integer, 1..3) {|x| @range = x}
    @topt = nil
    @opt.def_option("-n") {}
    @opt.def_option("--regexp [REGEXP]", Regexp) {|x| @reopt = x}
    @reopt = nil
    @opt.def_option "--with_underscore=VAL" do |x| @flag = x end
    @opt.def_option "--with-hyphen=VAL" do |x| @flag = x end
    @opt.def_option("--fallback [VAL]") do |x = "fallback"| @flag = x end
    @opt.def_option("--lambda [VAL]", &->(x) {@flag = x})
  end

  def test_short
    assert_equal(%w"", no_error {@opt.parse!(%w"-x -n")})
    assert_equal(nil, @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"-x -")})
    assert_equal("-", @flag)
    @flag = false
    assert_equal(%w"", no_error {@opt.parse!(%w"-x foo")})
    assert_equal("foo", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"-xbar")})
    assert_equal("bar", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"-x=")})
    assert_equal("=", @flag)
  end

  def test_abbrev
    assert_equal(%w"", no_error {@opt.parse!(%w"-o -n")})
    assert_equal(nil, @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"-o -")})
    assert_equal("-", @flag)
    @flag = false
    assert_equal(%w"", no_error {@opt.parse!(%w"-o foo")})
    assert_equal("foo", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"-obar")})
    assert_equal("bar", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"-o=")})
    assert_equal("=", @flag)
  end

  def test_long
    assert_equal(%w"", no_error {@opt.parse!(%w"--opt -n")})
    assert_equal(nil, @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"--opt -")})
    assert_equal("-", @flag)
    assert_equal(%w"foo", no_error {@opt.parse!(%w"--opt= foo")})
    assert_equal("", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"--opt=foo")})
    assert_equal("foo", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"--opt bar")})
    assert_equal("bar", @flag)
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

  def test_conv
    assert_equal(%w"te.rb", no_error('[ruby-dev:38333]') {@opt.parse!(%w"-T te.rb")})
    assert_nil(@topt)
    assert_equal(%w"te.rb", no_error('[ruby-dev:38333]') {@opt.parse!(%w"-T1 te.rb")})
    assert_equal(1, @topt)
  end

  def test_default_argument
    assert_equal(%w"", no_error {@opt.parse!(%w"--fallback=val1")})
    assert_equal("val1", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"--fallback val2")})
    assert_equal("val2", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"--fallback")})
    assert_equal("fallback", @flag)
  end

  def test_lambda
    assert_equal(%w"", no_error {@opt.parse!(%w"--lambda=lambda1")})
    assert_equal("lambda1", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"--lambda lambda2")})
    assert_equal("lambda2", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"--lambda")})
    assert_equal(nil, @flag)
  end

  def test_enum
    assert_equal([], no_error {@opt.parse!(%w"--enum=A")})
    assert_equal(:Alpha, @enum)
  end

  def test_enum_pair
    assert_equal([], no_error {@opt.parse!(%w"--enumval=A")})
    assert_equal(1, @enum)
  end

  def test_enum_conversion
    assert_equal([], no_error {@opt.parse!(%w"--integer=1")})
    assert_equal(1, @integer)
  end

  def test_enum_range
    assert_equal([], no_error {@opt.parse!(%w"--range=1")})
    assert_equal(1, @range)
    assert_raise(OptionParser::InvalidArgument) {@opt.parse!(%w"--range=4")}
  end
end
