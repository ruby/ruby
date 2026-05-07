# frozen_string_literal: true

module Bundler
  module FetchMetadata
    # A fallback is included because the original version of the specification
    # API didn't include that field, so some marshalled specs in the index have it
    # set to +nil+.
    def matches_current_ruby?
      ensure_required_ruby_version_loaded
      super
    end

    def matches_current_rubygems?
      ensure_required_rubygems_version_loaded
      super
    end

    def matches_current_ruby_with_overrides?(overrides)
      ensure_required_ruby_version_loaded
      super
    end

    def matches_current_rubygems_with_overrides?(overrides)
      ensure_required_rubygems_version_loaded
      super
    end

    private

    def ensure_required_ruby_version_loaded
      @required_ruby_version ||= _remote_specification.required_ruby_version || Gem::Requirement.default # rubocop:disable Naming/MemoizedInstanceVariableName
    end

    def ensure_required_rubygems_version_loaded
      @required_rubygems_version ||= _remote_specification.required_rubygems_version || Gem::Requirement.default # rubocop:disable Naming/MemoizedInstanceVariableName
    end
  end

  module MatchRemoteMetadata
    include MatchMetadata

    prepend FetchMetadata
  end
end
