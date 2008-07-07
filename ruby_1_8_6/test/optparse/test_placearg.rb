require 'test_optparse'

class TestOptionParser::PlaceArg < TestOptionParser
  def setup
    super
    @opt.def_option("-x [VAL]") {|x| @flag = x}
    @opt.def_option("--option [VAL]") {|x| @flag = x}
    @opt.def_option("-n") {}
  end

  def test_short
    assert_equal(%w"", no_error {@opt.parse!(%w"-x -n")})
    assert_equal(nil, @flag)
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
    assert_equal(%w"foo", no_error {@opt.parse!(%w"--opt= foo")})
    assert_equal("", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"--opt=foo")})
    assert_equal("foo", @flag)
    assert_equal(%w"", no_error {@opt.parse!(%w"--opt bar")})
    assert_equal("bar", @flag)
  end
end
