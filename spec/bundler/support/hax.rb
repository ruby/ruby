# frozen_string_literal: true

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

  if ENV["BUNDLER_SPEC_PLATFORM"]
    class Platform
      @local = new(ENV["BUNDLER_SPEC_PLATFORM"])
    end
    @platforms = [Gem::Platform::RUBY, Gem::Platform.local]

    if ENV["BUNDLER_SPEC_PLATFORM"] == "ruby"
      class << self
        remove_method :finish_resolve

        def finish_resolve
          []
        end
      end
    end
  end

  if ENV["BUNDLER_SPEC_GEM_SOURCES"]
    self.sources = [ENV["BUNDLER_SPEC_GEM_SOURCES"]]
  end

  # We only need this hack for rubygems versions without the BundlerVersionFinder
  if Gem.rubygems_version < Gem::Version.new("2.7.0")
    @path_to_default_spec_map.delete_if do |_path, spec|
      spec.name == "bundler"
    end
  end
end
