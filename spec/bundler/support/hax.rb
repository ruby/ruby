# frozen_string_literal: true

if ENV["BUNDLER_SPEC_RUBY_PLATFORM"]
  Object.send(:remove_const, :RUBY_PLATFORM)
  RUBY_PLATFORM = ENV["BUNDLER_SPEC_RUBY_PLATFORM"]
end

module Gem
  def self.ruby=(ruby)
    @ruby = ruby
  end

  if ENV["RUBY"]
    Gem.ruby = ENV["RUBY"]
  end

  if ENV["BUNDLER_GEM_DEFAULT_DIR"]
    @default_dir = ENV["BUNDLER_GEM_DEFAULT_DIR"]
    @default_specifications_dir = nil
  end

  spec_platform = ENV["BUNDLER_SPEC_PLATFORM"]
  if spec_platform
    if /mingw|mswin/.match?(spec_platform)
      @@win_platform = nil # rubocop:disable Style/ClassVars
      RbConfig::CONFIG["host_os"] = spec_platform.gsub(/^[^-]+-/, "").tr("-", "_")
    end

    RbConfig::CONFIG["arch"] = spec_platform

    class Platform
      @local = nil
    end
    @platforms = []
  end

  if ENV["BUNDLER_SPEC_GEM_SOURCES"]
    self.sources = [ENV["BUNDLER_SPEC_GEM_SOURCES"]]
  end

  if ENV["BUNDLER_SPEC_READ_ONLY"]
    module ReadOnly
      def open(file, mode)
        if file != IO::NULL && mode == "wb"
          raise Errno::EROFS
        else
          super
        end
      end
    end

    File.singleton_class.prepend ReadOnly
  end
end
