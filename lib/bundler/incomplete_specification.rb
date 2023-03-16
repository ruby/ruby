# frozen_string_literal: true

module Bundler
  #
  # Represents a package name that was found to be incomplete when trying to
  # materialize a fresh resolution or the lockfile.
  #
  # Holds the actual partially complete set of specifications for the name.
  # These are used so that they can be unlocked in a future resolution, and fix
  # the situation.
  #
  class IncompleteSpecification
    attr_reader :name, :partially_complete_specs

    def initialize(name, partially_complete_specs = [])
      @name = name
      @partially_complete_specs = partially_complete_specs
    end

    def ==(other)
      partially_complete_specs == other.partially_complete_specs
    end
  end
end
