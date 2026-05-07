# frozen_string_literal: true

module Bundler
  module MatchMetadata
    def matches_current_metadata?
      matches_current_ruby? && matches_current_rubygems?
    end

    def matches_current_ruby?
      effective_required_ruby_version.satisfied_by?(Gem.ruby_version)
    end

    def matches_current_rubygems?
      effective_required_rubygems_version.satisfied_by?(Gem.rubygems_version)
    end

    def expanded_dependencies
      runtime_dependencies + [
        metadata_dependency("Ruby", @required_ruby_version),
        metadata_dependency("RubyGems", @required_rubygems_version),
      ].compact
    end

    def metadata_dependency(name, requirement)
      return if requirement.nil? || requirement.none?

      Gem::Dependency.new("#{name}\0", requirement)
    end

    private

    def effective_required_ruby_version
      apply_metadata_override(@required_ruby_version, :required_ruby_version)
    end

    def effective_required_rubygems_version
      apply_metadata_override(@required_rubygems_version, :required_rubygems_version)
    end

    def apply_metadata_override(requirement, field)
      override = Override.find_for(Bundler.overrides, name, field)
      return requirement unless override
      override.apply_to(requirement)
    end
  end
end
