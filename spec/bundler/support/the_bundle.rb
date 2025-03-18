# frozen_string_literal: true

require_relative "path"

module Spec
  class TheBundle
    include Spec::Path

    attr_accessor :bundle_dir

    def initialize(opts = {})
      opts = opts.dup
      @bundle_dir = Pathname.new(opts.delete(:bundle_dir) { bundled_app })
      raise "Too many options! #{opts}" unless opts.empty?
    end

    def to_s
      "the bundle"
    end
    alias_method :inspect, :to_s

    def locked?
      lockfile.file?
    end

    def lockfile
      bundle_dir.join("Gemfile.lock")
    end

    def locked_gems
      raise "Cannot read lockfile if it doesn't exist" unless locked?
      Bundler::LockfileParser.new(lockfile.read)
    end

    def locked_specs
      locked_gems.specs.map(&:full_name)
    end

    def locked_platforms
      locked_gems.platforms.map(&:to_s)
    end
  end
end
