# frozen_string_literal: true

module Spec
  module Platforms
    include Bundler::GemHelpers

    def rb
      Gem::Platform::RUBY
    end

    def mac
      Gem::Platform.new("x86-darwin-10")
    end

    def x64_mac
      Gem::Platform.new("x86_64-darwin-15")
    end

    def java
      Gem::Platform.new([nil, "java", nil])
    end

    def linux
      Gem::Platform.new("x86_64-linux")
    end

    def x86_mswin32
      Gem::Platform.new(["x86", "mswin32", nil])
    end

    def x64_mswin64
      Gem::Platform.new(["x64", "mswin64", nil])
    end

    def x86_mingw32
      Gem::Platform.new(["x86", "mingw32", nil])
    end

    def x64_mingw32
      Gem::Platform.new(["x64", "mingw32", nil])
    end

    def x64_mingw_ucrt
      Gem::Platform.new(["x64", "mingw", "ucrt"])
    end

    def windows_platforms
      [x86_mswin32, x64_mswin64, x86_mingw32, x64_mingw32, x64_mingw_ucrt]
    end

    def all_platforms
      [rb, java, linux, windows_platforms].flatten
    end

    def specific_local_platform
      Bundler.local_platform
    end

    def not_local
      all_platforms.find {|p| p != generic_local_platform }
    end

    def local_tag
      if RUBY_PLATFORM == "java"
        :jruby
      elsif ["x64-mingw32", "x64-mingw-ucrt"].include?(RUBY_PLATFORM)
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

    def lockfile_platforms
      lockfile_platforms_for(specific_local_platform)
    end

    def lockfile_platforms_for(*platforms)
      platforms.map(&:to_s).sort.join("\n  ")
    end
  end
end
