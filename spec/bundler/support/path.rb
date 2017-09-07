# frozen_string_literal: true
require "pathname"

module Spec
  module Path
    def root
      if !!(ENV["BUNDLE_RUBY"] && ENV["BUNDLE_GEM"])
        # for Ruby Core
        root_path = File.expand_path("../../../..", __FILE__)
      else
        root_path = File.expand_path("../../..", __FILE__)
      end
      @root ||= Pathname.new(root_path)
    end

    def gemspec
      if !!(ENV["BUNDLE_RUBY"] && ENV["BUNDLE_GEM"])
        # for Ruby Core
        gemspec_path = File.expand_path(root.join("lib/bundler.gemspec"), __FILE__)
      else
        gemspec_path = File.expand_path(root.join("bundler.gemspec"), __FILE__)
      end
      @gemspec ||= Pathname.new(gemspec_path)
    end

    def bindir
      if !!(ENV["BUNDLE_RUBY"] && ENV["BUNDLE_GEM"])
        # for Ruby Core
        bin_path = File.expand_path(root.join("bin"), __FILE__)
      else
        bin_path = File.expand_path(root.join("exe"), __FILE__)
      end
      @bindir ||= Pathname.new(bin_path)
    end

    def spec_dir
      if !!(ENV["BUNDLE_RUBY"] && ENV["BUNDLE_GEM"])
        # for Ruby Core
        spec_path = File.expand_path(root.join("spec/bundler"), __FILE__)
      else
        spec_path = File.expand_path(root.join("spec"), __FILE__)
      end
      @spec_dir ||= Pathname.new(spec_path)
    end

    def tmp(*path)
      root.join("tmp", *path)
    end

    def home(*path)
      tmp.join("home", *path)
    end

    def default_bundle_path(*path)
      system_gem_path(*path)
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
  end
end
