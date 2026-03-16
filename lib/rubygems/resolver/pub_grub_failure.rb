# frozen_string_literal: true

class Gem::Resolver::PubGrubFailure
  attr_reader :solve_failure

  def initialize(solve_failure)
    @solve_failure = solve_failure
  end

  def explanation
    @solve_failure.explanation
  end

  def conflicting_dependencies
    terms = @solve_failure.incompatibility.terms
    terms.map {|t| t.package.to_s }
  end
end
