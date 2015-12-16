# frozen_string_literal: false
require 'rubygems/test_case'

class TestGemDependencyResolutionError < Gem::TestCase

  def setup
    super

    @DR = Gem::Resolver

    @spec = util_spec 'a', 2

    @a1_req = @DR::DependencyRequest.new dep('a', '= 1'), nil
    @a2_req = @DR::DependencyRequest.new dep('a', '= 2'), nil

    @activated = @DR::ActivationRequest.new @spec, @a2_req

    @conflict = @DR::Conflict.new @a1_req, @activated

    @error = Gem::DependencyResolutionError.new @conflict
  end

  def test_message
    assert_match %r%^conflicting dependencies a \(= 1\) and a \(= 2\)$%,
                 @error.message
  end

end

