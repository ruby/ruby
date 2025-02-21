# frozen_string_literal: true

require_relative "rubygems_ext"

module Bundler
  # Returns current version of Ruby
  #
  # @return [CurrentRuby] Current version of Ruby
  def self.current_ruby
    @current_ruby ||= CurrentRuby.new
  end

  class CurrentRuby
    ALL_RUBY_VERSIONS = (18..27).to_a.concat((30..35).to_a).freeze
    KNOWN_MINOR_VERSIONS = ALL_RUBY_VERSIONS.map {|v| v.digits.reverse.join(".") }.freeze
    KNOWN_MAJOR_VERSIONS = ALL_RUBY_VERSIONS.map {|v| v.digits.last.to_s }.uniq.freeze
    PLATFORM_MAP = {
      ruby: [Gem::Platform::RUBY, CurrentRuby::ALL_RUBY_VERSIONS],
      mri: [Gem::Platform::RUBY, CurrentRuby::ALL_RUBY_VERSIONS],
      rbx: [Gem::Platform::RUBY],
      truffleruby: [Gem::Platform::RUBY],
      jruby: [Gem::Platform::JAVA, [18, 19]],
      windows: [Gem::Platform::WINDOWS, CurrentRuby::ALL_RUBY_VERSIONS],
      # deprecated
      mswin: [Gem::Platform::MSWIN, CurrentRuby::ALL_RUBY_VERSIONS],
      mswin64: [Gem::Platform::MSWIN64, CurrentRuby::ALL_RUBY_VERSIONS - [18]],
      mingw: [Gem::Platform::UNIVERSAL_MINGW, CurrentRuby::ALL_RUBY_VERSIONS],
      x64_mingw: [Gem::Platform::UNIVERSAL_MINGW, CurrentRuby::ALL_RUBY_VERSIONS - [18, 19]],
    }.each_with_object({}) do |(platform, spec), hash|
      hash[platform] = spec[0]
      spec[1]&.each {|version| hash[:"#{platform}_#{version}"] = spec[0] }
    end.freeze

    def ruby?
      return true if Bundler::GemHelpers.generic_local_platform_is_ruby?

      !windows? && (RUBY_ENGINE == "ruby" || RUBY_ENGINE == "rbx" || RUBY_ENGINE == "maglev" || RUBY_ENGINE == "truffleruby")
    end

    def mri?
      !windows? && RUBY_ENGINE == "ruby"
    end

    def rbx?
      ruby? && RUBY_ENGINE == "rbx"
    end

    def jruby?
      RUBY_ENGINE == "jruby"
    end

    def maglev?
      RUBY_ENGINE == "maglev"
    end

    def truffleruby?
      RUBY_ENGINE == "truffleruby"
    end

    def windows?
      Gem.win_platform?
    end
    alias_method :mswin?, :windows?
    alias_method :mswin64?, :windows?
    alias_method :mingw?, :windows?
    alias_method :x64_mingw?, :windows?

    (KNOWN_MINOR_VERSIONS + KNOWN_MAJOR_VERSIONS).each do |version|
      trimmed_version = version.tr(".", "")
      define_method(:"on_#{trimmed_version}?") do
        RUBY_VERSION.start_with?("#{version}.")
      end

      all_platforms = PLATFORM_MAP.keys << "maglev"
      all_platforms.each do |platform|
        define_method(:"#{platform}_#{trimmed_version}?") do
          send(:"#{platform}?") && send(:"on_#{trimmed_version}?")
        end
      end
    end
  end
end
