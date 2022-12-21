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

  if ENV["BUNDLER_SPEC_WINDOWS"]
    @@win_platform = true # rubocop:disable Style/ClassVars
  end

  if ENV["BUNDLER_SPEC_PLATFORM"]
    class Platform
      @local = new(ENV["BUNDLER_SPEC_PLATFORM"])
    end
    @platforms = [Gem::Platform::RUBY, Gem::Platform.local]
  end

  if ENV["BUNDLER_SPEC_GEM_SOURCES"]
    self.sources = [ENV["BUNDLER_SPEC_GEM_SOURCES"]]
  end
end
