# frozen_string_literal: false
module Gem::Resolver::Molinillo
  # A state that a {Resolution} can be in
  # @attr [String] name
  # @attr [Array<Object>] requirements
  # @attr [DependencyGraph] activated
  # @attr [Object] requirement
  # @attr [Object] possibility
  # @attr [Integer] depth
  # @attr [Set<Object>] conflicts
  ResolutionState = Struct.new(
    :name,
    :requirements,
    :activated,
    :requirement,
    :possibilities,
    :depth,
    :conflicts
  )

  class ResolutionState
    # Returns an empty resolution state
    # @return [ResolutionState] an empty state
    def self.empty
      new(nil, [], DependencyGraph.new, nil, nil, 0, Set.new)
    end
  end

  # A state that encapsulates a set of {#requirements} with an {Array} of
  # possibilities
  class DependencyState < ResolutionState
    # Removes a possibility from `self`
    # @return [PossibilityState] a state with a single possibility,
    #  the possibility that was removed from `self`
    def pop_possibility_state
      PossibilityState.new(
        name,
        requirements.dup,
        activated.dup,
        requirement,
        [possibilities.pop],
        depth + 1,
        conflicts.dup
      )
    end
  end

  # A state that encapsulates a single possibility to fulfill the given
  # {#requirement}
  class PossibilityState < ResolutionState
  end
end
