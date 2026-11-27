# frozen_string_literal: true

module Bundler
  module MatchMetadata
    def matches_current_metadata?
      matches_current_ruby? && matches_current_rubygems?
    end

    def matches_current_ruby?
      @required_ruby_version.satisfied_by?(Gem.ruby_version)
    end

    def matches_current_rubygems?
      @required_rubygems_version.satisfied_by?(Gem.rubygems_version)
    end

    def matches_current_metadata_with_overrides?(overrides)
      matches_current_ruby_with_overrides?(overrides) && matches_current_rubygems_with_overrides?(overrides)
    end

    def matches_current_ruby_with_overrides?(overrides)
      effective_required_version(@required_ruby_version, :required_ruby_version, overrides).satisfied_by?(Gem.ruby_version)
    end

    def matches_current_rubygems_with_overrides?(overrides)
      effective_required_version(@required_rubygems_version, :required_rubygems_version, overrides).satisfied_by?(Gem.rubygems_version)
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

    def effective_required_version(requirement, field, overrides)
      return requirement if overrides.nil? || overrides.empty?
      override = Override.find_for(overrides, name, field)
      override ? override.apply_to(requirement) : requirement
    end
  end
end
