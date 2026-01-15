# frozen_string_literal: true

module Bundler
  module MatchPlatform
    def installable_on_platform?(target_platform) # :nodoc:
      return true if [Gem::Platform::RUBY, nil, target_platform].include?(platform)
      return true if Gem::Platform.new(platform) === target_platform

      false
    end

    def self.select_best_platform_match(specs, platform, force_ruby: false, prefer_locked: false)
      matching = select_all_platform_match(specs, platform, force_ruby: force_ruby, prefer_locked: prefer_locked)

      Gem::Platform.sort_and_filter_best_platform_match(matching, platform)
    end

    def self.select_best_local_platform_match(specs, force_ruby: false)
      local = Bundler.local_platform
      matching = select_all_platform_match(specs, local, force_ruby: force_ruby).filter_map(&:materialized_for_installation)

      Gem::Platform.sort_best_platform_match(matching, local)
    end

    def self.select_all_platform_match(specs, platform, force_ruby: false, prefer_locked: false)
      matching = specs.select {|spec| spec.installable_on_platform?(force_ruby ? Gem::Platform::RUBY : platform) }

      specs.each(&:force_ruby_platform!) if force_ruby

      if prefer_locked
        locked_originally = matching.select {|spec| spec.is_a?(::Bundler::LazySpecification) }
        return locked_originally if locked_originally.any?
      end

      matching
    end

    def self.generic_local_platform_is_ruby?
      Bundler.generic_local_platform == Gem::Platform::RUBY
    end
  end
end
