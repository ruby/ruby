# frozen_string_literal: false

require 'test/unit'
require 'optparse'


class TestOptionParserSwitch < Test::Unit::TestCase

  def setup
    @parser = OptionParser.new
  end

  def assert_invalidarg_error(msg, &block)
    exc = assert_raise(OptionParser::InvalidArgument) do
      yield
    end
    assert_equal "invalid argument: #{msg}", exc.message
  end

  def test_make_switch__enum_array
    p = @parser
    p.on("--enum=<val>", ["aa", "bb", "cc"])
    p.permute(["--enum=bb"], into: (opts={}))
    assert_equal({:enum=>"bb"}, opts)
    assert_invalidarg_error("--enum=dd") do
      p.permute(["--enum=dd"], into: (opts={}))
    end
  end

  def test_make_switch__enum_hash
    p = @parser
    p.on("--hash=<val>", {"aa"=>"AA", "bb"=>"BB"})
    p.permute(["--hash=bb"], into: (opts={}))
    assert_equal({:hash=>"BB"}, opts)
    assert_invalidarg_error("--hash=dd") do
      p.permute(["--hash=dd"], into: (opts={}))
    end
  end

  def test_make_switch__enum_set
    p = @parser
    p.on("--set=<val>", Set.new(["aa", "bb", "cc"]))
    p.permute(["--set=bb"], into: (opts={}))
    assert_equal({:set=>"bb"}, opts)
    assert_invalidarg_error("--set=dd") do
      p.permute(["--set=dd"], into: (opts={}))
    end
  end

end
