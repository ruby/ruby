# frozen_string_literal: false
require_relative 'test_optparse'
begin
  require "did_you_mean"
rescue LoadError
  return
end

class TestOptionParserDidYouMean < TestOptionParser
  def setup
    super
    @opt.def_option("--foo", Integer) { |v| @foo = v }
    @opt.def_option("--bar", Integer) { |v| @bar = v }
    @opt.def_option("--baz", Integer) { |v| @baz = v }
    @formatter = ::DidYouMean.formatter
    if ::DidYouMean.const_defined?(:Formatter)
      ::DidYouMean.formatter = ::DidYouMean::Formatter
    else
      case @formatter
      when ::DidYouMean::PlainFormatter
      else
        ::DidYouMean.formatter = ::DidYouMean::PlainFormatter.new
      end
    end
  end

  def teardown
    ::DidYouMean.formatter = @formatter
  end

  def test_no_suggestion
    assert_raise_with_message(OptionParser::InvalidOption, "invalid option: --cuz") do
      @opt.permute!(%w"--cuz")
    end
  end

  def test_plain
    assert_raise_with_message(OptionParser::InvalidOption, /invalid option: --baa\nDid you mean\?\s+bar\s+baz\Z/) do
      @opt.permute!(%w"--baa")
    end
  end

  def test_ambiguous
    assert_raise_with_message(OptionParser::AmbiguousOption, /ambiguous option: --ba\nDid you mean\?\s+bar\s+baz\Z/) do
      @opt.permute!(%w"--ba")
    end
  end
end
