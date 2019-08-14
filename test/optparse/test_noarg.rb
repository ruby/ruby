# frozen_string_literal: false
require_relative 'test_optparse'

module TestOptionParser::NoArg
  def setup
    super
    @opt.def_option "--with_underscore" do |x| @flag = x end
    @opt.def_option "--with-hyphen" do |x| @flag = x end
  end

  class Def1 < TestOptionParser
    include NoArg
    def setup
      super
      @opt.def_option("-x") {|x| @flag = x}
      @opt.def_option("--option") {|x| @flag = x}
    end
  end
  class Def2 < TestOptionParser
    include NoArg
    def setup
      super
      @opt.def_option("-x", "--option") {|x| @flag = x}
    end
  end

  def test_short
    assert_raise(OptionParser::InvalidOption) {@opt.parse!(%w"-xq")}
    assert_equal(%w"", no_error {@opt.parse!(%w"-x")})
    assert_equal(true, @flag)
    @flag = nil
    assert_equal(%w"foo", no_error {@opt.parse!(%w"-x foo")})
    assert_equal(true, @flag)
  end

  def test_abbrev
    assert_raise(OptionParser::InvalidOption) {@opt.parse!(%w"-oq")}
    assert_equal(%w"", no_error {@opt.parse!(%w"-o")})
    assert_equal(true, @flag)
    @flag = nil
    assert_raise(OptionParser::InvalidOption) {@opt.parse!(%w"-O")}
    assert_nil(@flag)
    @flag = nil
    assert_equal(%w"foo", no_error {@opt.parse!(%w"-o foo")})
    assert_equal(true, @flag)
  end

  def test_long
    assert_raise(OptionParser::NeedlessArgument) {@opt.parse!(%w"--option=x")}
    assert_equal(%w"", no_error {@opt.parse!(%w"--opt")})
    assert_equal(true, @flag)
    @flag = nil
    assert_equal(%w"foo", no_error {@opt.parse!(%w"--opt foo")})
    assert_equal(true, @flag)
  end

  def test_ambiguous
    @opt.def_option("--open") {|x|}
    assert_raise(OptionParser::AmbiguousOption) {@opt.parse!(%w"--op")}
    assert_raise(OptionParser::AmbiguousOption) {@opt.parse!(%w"-o")}
    assert_equal(%w"", no_error {@opt.parse!(%w"--opt")})
    assert_equal(true, @flag)
  end

  def test_hyphenize
    @flag = nil
    assert_equal(%w"", no_error {@opt.parse!(%w"--with_underscore")})
    assert_equal(true, @flag)
    @flag = nil
    assert_equal(%w"", no_error {@opt.parse!(%w"--with-underscore")})
    assert_equal(true, @flag)
    @flag = nil
    assert_equal(%w"", no_error {@opt.parse!(%w"--with-hyphen")})
    assert_equal(true, @flag)
    @flag = nil
    assert_equal(%w"", no_error {@opt.parse!(%w"--with_hyphen")})
    assert_equal(true, @flag)
  end
end
