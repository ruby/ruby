# frozen_string_literal: false
require_relative 'test_optparse'
require "did_you_mean" rescue return

class TestOptionParser::DidYouMean < TestOptionParser
  def setup
    super
    @opt.def_option("--foo", Integer) { |v| @foo = v }
    @opt.def_option("--bar", Integer) { |v| @bar = v }
    @opt.def_option("--baz", Integer) { |v| @baz = v }
    @formatter = ::DidYouMean.formatter
  end

  def teardown
    ::DidYouMean.formatter = @formatter
  end


  def test_plain
    ::DidYouMean.formatter = ::DidYouMean::PlainFormatter.new
    assert_raise_with_message(OptionParser::InvalidOption, /invalid option: --baa\nDid you mean\?\s+baz\s+bar\Z/) do
      @opt.permute!(%w"--baa")
    end
  end

  def test_verbose
    require 'did_you_mean/formatters/verbose_formatter'
    ::DidYouMean.formatter = ::DidYouMean::VerboseFormatter.new
    assert_raise_with_message(OptionParser::InvalidOption, /invalid option: --baa\n\s+Did you mean\?\s+baz\s+bar\s*\Z/) do
      @opt.permute!(%w"--baa")
    end
  end
end
