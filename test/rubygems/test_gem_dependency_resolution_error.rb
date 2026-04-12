# frozen_string_literal: true

require_relative "helper"

class TestGemDependencyResolutionError < Gem::TestCase
  def setup
    super

    @spec = util_spec "a", 2

    @a1_req = Gem::Resolver::DependencyRequest.new dep("a", "= 1"), nil
    @a2_req = Gem::Resolver::DependencyRequest.new dep("a", "= 2"), nil

    @activated = Gem::Resolver::ActivationRequest.new @spec, @a2_req

    @conflict = Gem::Resolver::Conflict.new @a1_req, @activated

    @error = Gem::DependencyResolutionError.new @conflict
  end

  def test_message
    assert_match(/Activated a-2/, @error.message)
    assert_match(/conflicting dependency/, @error.message)
  end

  def test_conflict
    assert_nil @error.conflict
  end

  def test_conflicting_dependencies
    assert_equal [], @error.conflicting_dependencies
  end
end
