require_relative 'helper'
require "reline"

class Reline::TestKey < Reline::TestCase
  def test_match_symbol
    assert(Reline::Key.new(:key1, :key1, false).match?(:key1))
    refute(Reline::Key.new(:key1, :key1, false).match?(:key2))
    refute(Reline::Key.new(:key1, :key1, false).match?(nil))
    refute(Reline::Key.new(1, 1, false).match?(:key1))
  end
end
