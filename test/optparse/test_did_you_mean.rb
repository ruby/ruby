# frozen_string_literal: false
require_relative 'test_optparse'
require "did_you_mean" rescue return

class TestOptionParser::DidYouMean < TestOptionParser
  def setup
    super
    @opt.def_option("--foo", Integer) { |v| @foo = v }
    @opt.def_option("--bar", Integer) { |v| @bar = v }
    @opt.def_option("--baz", Integer) { |v| @baz = v }
  end

  def test_did_you_mean
    assert_raise(OptionParser::InvalidOption) do
      begin
        @opt.permute!(%w"--baa")
      ensure
        assert_equal("invalid option: --baa\nDid you mean?  baz\n               bar", $!.message)
      end
    end
  end
end
