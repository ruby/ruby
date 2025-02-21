# frozen_string_literal: true

require "rubygems/dependency"
require_relative "shared_helpers"

module Bundler
  class Dependency < Gem::Dependency
    def initialize(name, version, options = {}, &blk)
      type = options["type"] || :runtime
      super(name, version, type)

      @options = options
    end

    def groups
      @groups ||= Array(@options["group"] || :default).map(&:to_sym)
    end

    def source
      return @source if defined?(@source)

      @source = @options["source"]
    end

    def path
      return @path if defined?(@path)

      @path = @options["path"]
    end

    def git
      return @git if defined?(@git)

      @git = @options["git"]
    end

    def github
      return @github if defined?(@github)

      @github = @options["github"]
    end

    def branch
      return @branch if defined?(@branch)

      @branch = @options["branch"]
    end

    def ref
      return @ref if defined?(@ref)

      @ref = @options["ref"]
    end

    def glob
      return @glob if defined?(@glob)

      @glob = @options["glob"]
    end

    def platforms
      @platforms ||= Array(@options["platforms"])
    end

    def env
      return @env if defined?(@env)

      @env = @options["env"]
    end

    def should_include
      @should_include ||= @options.fetch("should_include", true)
    end

    def gemfile
      return @gemfile if defined?(@gemfile)

      @gemfile = @options["gemfile"]
    end

    def force_ruby_platform
      return @force_ruby_platform if defined?(@force_ruby_platform)

      @force_ruby_platform = @options["force_ruby_platform"]
    end

    def autorequire
      return @autorequire if defined?(@autorequire)

      @autorequire = Array(@options["require"] || []) if @options.key?("require")
    end

    RUBY_PLATFORM_ARRAY = [Gem::Platform::RUBY].freeze
    private_constant :RUBY_PLATFORM_ARRAY

    # Returns the platforms this dependency is valid for, in the same order as
    # passed in the `valid_platforms` parameter
    def gem_platforms(valid_platforms)
      return RUBY_PLATFORM_ARRAY if force_ruby_platform
      return valid_platforms if platforms.empty?

      valid_platforms.select {|p| expanded_platforms.include?(GemHelpers.generic(p)) }
    end

    def expanded_platforms
      @expanded_platforms ||= platforms.filter_map {|pl| CurrentRuby::PLATFORM_MAP[pl] }.flatten.uniq
    end

    def should_include?
      should_include && current_env? && current_platform?
    end

    def gemspec_dev_dep?
      @gemspec_dev_dep ||= @options.fetch("gemspec_dev_dep", false)
    end

    def gemfile_dep?
      !gemspec_dev_dep?
    end

    def current_env?
      return true unless env
      if env.is_a?(Hash)
        env.all? do |key, val|
          ENV[key.to_s] && (val.is_a?(String) ? ENV[key.to_s] == val : ENV[key.to_s] =~ val)
        end
      else
        ENV[env.to_s]
      end
    end

    def current_platform?
      return true if platforms.empty?
      platforms.any? do |p|
        Bundler.current_ruby.send("#{p}?")
      end
    end

    def to_lock
      out = super
      out << "!" if source
      out
    end

    def specific?
      super
    rescue NoMethodError
      requirement != ">= 0"
    end
  end
end
