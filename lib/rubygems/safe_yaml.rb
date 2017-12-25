module Gem

  ###
  # This module is used for safely loading YAML specs from a gem.  The
  # `safe_load` method defined on this module is specifically designed for
  # loading Gem specifications.  For loading other YAML safely, please see
  # Psych.safe_load

  module SafeYAML
    WHITELISTED_CLASSES = %w(
      Symbol
      Time
      Date
      Gem::Dependency
      Gem::Platform
      Gem::Requirement
      Gem::Specification
      Gem::Version
      Gem::Version::Requirement
      YAML::Syck::DefaultKey
      Syck::DefaultKey
    )

    WHITELISTED_SYMBOLS = %w(
      development
      runtime
    )

    if ::YAML.respond_to? :safe_load
      def self.safe_load input
        ::YAML.safe_load(input, WHITELISTED_CLASSES, WHITELISTED_SYMBOLS, true)
      end

      def self.load input
        ::YAML.safe_load(input, [::Symbol])
      end
    else
      unless Gem::Deprecate.skip
        warn "YAML safe loading is not available. Please upgrade psych to a version that supports safe loading (>= 2.0)."
      end

      def self.safe_load input, *args
        ::YAML.load input
      end

      def self.load input
        ::YAML.load input
      end
    end
  end
end
