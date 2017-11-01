# frozen_string_literal: true

require "pathname"

module Spec
  module Path
    def root
      @root ||=
        Pathname.new(for_ruby_core? ? "../../../.." : "../../..").expand_path(__FILE__)
    end

    def gemspec
      @gemspec ||= root.join(for_ruby_core? ? "lib/bundler.gemspec" : "bundler.gemspec")
    end

    def bindir
      @bindir ||= root.join(for_ruby_core? ? "bin" : "exe")
    end

    def spec_dir
      @spec_dir ||= root.join(for_ruby_core? ? "spec/bundler" : "spec")
    end

    def tmp(*path)
      root.join("tmp", *path)
    end

    def home(*path)
      tmp.join("home", *path)
    end

    def default_bundle_path(*path)
      if Bundler::VERSION.split(".").first.to_i < 2
        system_gem_path(*path)
      else
        bundled_app(*[".bundle", ENV.fetch("BUNDLER_SPEC_RUBY_ENGINE", Gem.ruby_engine), Gem::ConfigMap[:ruby_version], *path].compact)
      end
    end

    def bundled_app(*path)
      root = tmp.join("bundled_app")
      FileUtils.mkdir_p(root)
      root.join(*path)
    end

    alias_method :bundled_app1, :bundled_app

    def bundled_app2(*path)
      root = tmp.join("bundled_app2")
      FileUtils.mkdir_p(root)
      root.join(*path)
    end

    def vendored_gems(path = nil)
      bundled_app(*["vendor/bundle", Gem.ruby_engine, Gem::ConfigMap[:ruby_version], path].compact)
    end

    def cached_gem(path)
      bundled_app("vendor/cache/#{path}.gem")
    end

    def base_system_gems
      tmp.join("gems/base")
    end

    def gem_repo1(*args)
      tmp("gems/remote1", *args)
    end

    def gem_repo_missing(*args)
      tmp("gems/missing", *args)
    end

    def gem_repo2(*args)
      tmp("gems/remote2", *args)
    end

    def gem_repo3(*args)
      tmp("gems/remote3", *args)
    end

    def gem_repo4(*args)
      tmp("gems/remote4", *args)
    end

    def security_repo(*args)
      tmp("gems/security_repo", *args)
    end

    def system_gem_path(*path)
      tmp("gems/system", *path)
    end

    def lib_path(*args)
      tmp("libs", *args)
    end

    def bundler_path
      Pathname.new(File.expand_path(root.join("lib"), __FILE__))
    end

    def global_plugin_gem(*args)
      home ".bundle", "plugin", "gems", *args
    end

    def local_plugin_gem(*args)
      bundled_app ".bundle", "plugin", "gems", *args
    end

    def tmpdir(*args)
      tmp "tmpdir", *args
    end

    extend self

    private
    def for_ruby_core?
      # avoid to wornings
      @for_ruby_core ||= nil

      if @for_ruby_core.nil?
        @for_ruby_core = true & (ENV["BUNDLE_RUBY"] && ENV["BUNDLE_GEM"])
      else
        @for_ruby_core
      end
    end
  end
end
