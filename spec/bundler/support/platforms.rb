# frozen_string_literal: true

module Spec
  module Platforms
    def not_local
      generic_local_platform == Gem::Platform::RUBY ? "java" : Gem::Platform::RUBY
    end

    def local_platform
      Bundler.local_platform
    end

    def generic_local_platform
      Gem::Platform.generic(local_platform)
    end

    def local_tag
      if Gem.java_platform?
        :jruby
      elsif Gem.win_platform?
        :windows
      else
        :ruby
      end
    end

    def not_local_tag
      [:jruby, :windows, :ruby].find {|tag| tag != local_tag }
    end

    def local_ruby_engine
      RUBY_ENGINE
    end

    def local_engine_version
      RUBY_ENGINE == "ruby" ? Gem.ruby_version : RUBY_ENGINE_VERSION
    end

    def not_local_engine_version
      case not_local_tag
      when :ruby, :windows
        not_local_ruby_version
      when :jruby
        "1.6.1"
      end
    end

    def not_local_ruby_version
      "1.12"
    end

    def not_local_patchlevel
      9999
    end

    def default_platform_list(*extra, defaults: default_locked_platforms)
      defaults.concat(extra).map(&:to_s).uniq
    end

    def lockfile_platforms(*extra, defaults: default_locked_platforms)
      platforms = default_platform_list(*extra, defaults: defaults)
      platforms.sort.join("\n  ")
    end

    def default_locked_platforms
      [local_platform, generic_default_locked_platform].compact
    end

    def generic_default_locked_platform
      return unless Bundler::MatchPlatform.generic_local_platform_is_ruby?

      Gem::Platform::RUBY
    end
  end
end
