# frozen_string_literal: true

module Bundler
  module GemHelpers
    GENERIC_CACHE = { Gem::Platform::RUBY => Gem::Platform::RUBY } # rubocop:disable Style/MutableConstant
    GENERICS = [
      [Gem::Platform.new("java"), Gem::Platform.new("java")],
      [Gem::Platform.new("mswin32"), Gem::Platform.new("mswin32")],
      [Gem::Platform.new("mswin64"), Gem::Platform.new("mswin64")],
      [Gem::Platform.new("universal-mingw32"), Gem::Platform.new("universal-mingw32")],
      [Gem::Platform.new("x64-mingw32"), Gem::Platform.new("x64-mingw32")],
      [Gem::Platform.new("x86_64-mingw32"), Gem::Platform.new("x64-mingw32")],
      [Gem::Platform.new("mingw32"), Gem::Platform.new("x86-mingw32")],
    ].freeze

    def generic(p)
      GENERIC_CACHE[p] ||= begin
        _, found = GENERICS.find do |match, _generic|
          p.os == match.os && (!match.cpu || p.cpu == match.cpu)
        end
        found || Gem::Platform::RUBY
      end
    end
    module_function :generic

    def generic_local_platform
      generic(local_platform)
    end
    module_function :generic_local_platform

    def local_platform
      Bundler.local_platform
    end
    module_function :local_platform

    def platform_specificity_match(spec_platform, user_platform)
      spec_platform = Gem::Platform.new(spec_platform)
      return PlatformMatch::EXACT_MATCH if spec_platform == user_platform
      return PlatformMatch::WORST_MATCH if spec_platform.nil? || spec_platform == Gem::Platform::RUBY || user_platform == Gem::Platform::RUBY

      PlatformMatch.new(
        PlatformMatch.os_match(spec_platform, user_platform),
        PlatformMatch.cpu_match(spec_platform, user_platform),
        PlatformMatch.platform_version_match(spec_platform, user_platform)
      )
    end
    module_function :platform_specificity_match

    def select_best_platform_match(specs, platform)
      specs.select {|spec| spec.match_platform(platform) }.
        min_by {|spec| platform_specificity_match(spec.platform, platform) }
    end
    module_function :select_best_platform_match

    PlatformMatch = Struct.new(:os_match, :cpu_match, :platform_version_match)
    class PlatformMatch
      def <=>(other)
        return nil unless other.is_a?(PlatformMatch)

        m = os_match <=> other.os_match
        return m unless m.zero?

        m = cpu_match <=> other.cpu_match
        return m unless m.zero?

        m = platform_version_match <=> other.platform_version_match
        m
      end

      EXACT_MATCH = new(-1, -1, -1).freeze
      WORST_MATCH = new(1_000_000, 1_000_000, 1_000_000).freeze

      def self.os_match(spec_platform, user_platform)
        if spec_platform.os == user_platform.os
          0
        else
          1
        end
      end

      def self.cpu_match(spec_platform, user_platform)
        if spec_platform.cpu == user_platform.cpu
          0
        elsif spec_platform.cpu == "arm" && user_platform.cpu.to_s.start_with?("arm")
          0
        elsif spec_platform.cpu.nil? || spec_platform.cpu == "universal"
          1
        else
          2
        end
      end

      def self.platform_version_match(spec_platform, user_platform)
        if spec_platform.version == user_platform.version
          0
        elsif spec_platform.version.nil?
          1
        else
          2
        end
      end
    end
  end
end
