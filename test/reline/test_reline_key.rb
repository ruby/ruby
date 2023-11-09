require_relative 'helper'
require "reline"

class Reline::TestKey < Reline::TestCase
  def setup
    Reline.test_mode
  end

  def teardown
    Reline.test_reset
  end

  def test_match_key
    assert(Reline::Key.new(1, 2, false).match?(Reline::Key.new(1, 2, false)))
    assert(Reline::Key.new(1, 2, false).match?(Reline::Key.new(nil, 2, false)))
    assert(Reline::Key.new(1, 2, false).match?(Reline::Key.new(1, 2, nil)))

    assert(Reline::Key.new(nil, 2, false).match?(Reline::Key.new(nil, 2, false)))
    assert(Reline::Key.new(1, nil, false).match?(Reline::Key.new(1, nil, false)))
    assert(Reline::Key.new(1, 2, nil).match?(Reline::Key.new(1, 2, nil)))

    assert(Reline::Key.new(nil, 2, false).match?(Reline::Key.new(nil, 2, false)))
    assert(Reline::Key.new(1, nil, false).match?(Reline::Key.new(1, nil, false)))
    assert(Reline::Key.new(1, 2, nil).match?(Reline::Key.new(1, 2, nil)))

    assert(!Reline::Key.new(1, 2, false).match?(Reline::Key.new(3, 1, false)))
    assert(!Reline::Key.new(1, 2, false).match?(Reline::Key.new(1, 3, false)))
    assert(!Reline::Key.new(1, 2, false).match?(Reline::Key.new(1, 3, true)))
  end

  def test_match_integer
    assert(Reline::Key.new(1, 2, false).match?(2))
    assert(Reline::Key.new(nil, 2, false).match?(2))
    assert(Reline::Key.new(1, nil, false).match?(1))

    assert(!Reline::Key.new(1, 2, false).match?(1))
    assert(!Reline::Key.new(1, nil, false).match?(2))
    assert(!Reline::Key.new(nil, nil, false).match?(1))
  end

  def test_match_symbol
    assert(Reline::Key.new(:key1, :key2, false).match?(:key2))
    assert(Reline::Key.new(:key1, nil, false).match?(:key1))

    assert(!Reline::Key.new(:key1, :key2, false).match?(:key1))
    assert(!Reline::Key.new(:key1, nil, false).match?(:key2))
    assert(!Reline::Key.new(nil, nil, false).match?(:key1))
  end

  def test_match_other
    assert(!Reline::Key.new(:key1, 2, false).match?("key1"))
    assert(!Reline::Key.new(nil, nil, false).match?(nil))
  end
end
