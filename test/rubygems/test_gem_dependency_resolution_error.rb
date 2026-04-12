# frozen_string_literal: true

require_relative "helper"

class TestGemDependencyResolutionError < Gem::TestCase
  def setup
    super

    failure = Struct.new(:explanation).new("a depends on b (= 1.0) but no versions match")
    @error = Gem::DependencyResolutionError.new failure
  end

  def test_message
    assert_equal "a depends on b (= 1.0) but no versions match", @error.message
  end

  def test_explanation
    assert_equal "a depends on b (= 1.0) but no versions match", @error.explanation
  end

  def test_conflict
    assert_nil @error.conflict
  end

  def test_conflicting_dependencies
    assert_equal [], @error.conflicting_dependencies
  end
end
