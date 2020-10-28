# frozen_string_literal: true

module Gem
  def self.ruby=(ruby)
    @ruby = ruby
  end

  if ENV["RUBY"]
    Gem.ruby = ENV["RUBY"]
  end

  @default_dir = ENV["BUNDLER_GEM_DEFAULT_DIR"] if ENV["BUNDLER_GEM_DEFAULT_DIR"]

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

  # We only need this hack for rubygems versions without the BundlerVersionFinder
  if Gem::Version.new(Gem::VERSION) < Gem::Version.new("2.7.0")
    @path_to_default_spec_map.delete_if do |_path, spec|
      spec.name == "bundler"
    end
  end
end

if ENV["BUNDLER_SPEC_WINDOWS"] == "true"
  require_relative "path"
  require "bundler/constants"

  module Bundler
    remove_const :WINDOWS if defined?(WINDOWS)
    WINDOWS = true
  end
end

if ENV["BUNDLER_SPEC_API_REQUEST_LIMIT"]
  require_relative "path"
  require "bundler/source"
  require "bundler/source/rubygems"

  module Bundler
    class Source
      class Rubygems < Source
        remove_const :API_REQUEST_LIMIT
        API_REQUEST_LIMIT = ENV["BUNDLER_SPEC_API_REQUEST_LIMIT"].to_i
      end
    end
  end
end
