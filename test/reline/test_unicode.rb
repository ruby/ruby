require_relative 'helper'
require "reline/unicode"

class Reline::Unicode::Test < Reline::TestCase
  def setup
    Reline.send(:test_mode)
  end

  def test_get_mbchar_width
    assert_equal Reline.ambiguous_width, Reline::Unicode.get_mbchar_width('é')
  end
end
