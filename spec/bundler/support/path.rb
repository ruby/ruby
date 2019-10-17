# frozen_string_literal: true

require "pathname"
require "rbconfig"

module Spec
  module Path
    def root
      @root ||= Pathname.new(ruby_core? ? "../../../.." : "../../..").expand_path(__FILE__)
    end

    def gemspec
      @gemspec ||= root.join(ruby_core? ? "lib/bundler/bundler.gemspec" : "bundler.gemspec")
    end

    def gemspec_dir
      @gemspec_dir ||= gemspec.parent
    end

    def bindir
      @bindir ||= root.join(ruby_core? ? "libexec" : "exe")
    end

    def gem_bin
      @gem_bin ||= ruby_core? ? ENV["GEM_COMMAND"] : "#{Gem.ruby} -S gem --backtrace"
    end

    def spec_dir
      @spec_dir ||= root.join(ruby_core? ? "spec/bundler" : "spec")
    end

    def tracked_files
      @tracked_files ||= ruby_core? ? `git ls-files -z -- lib/bundler lib/bundler.rb spec/bundler man/bundler*` : `git ls-files -z`
    end

    def shipped_files
      @shipped_files ||= ruby_core? ? `git ls-files -z -- lib/bundler lib/bundler.rb man/bundler* libexec/bundle*` : `git ls-files -z -- lib man exe CHANGELOG.md LICENSE.md README.md bundler.gemspec`
    end

    def lib_tracked_files
      @lib_tracked_files ||= ruby_core? ? `git ls-files -z -- lib/bundler lib/bundler.rb` : `git ls-files -z -- lib`
    end

    def tmp(*path)
      root.join("tmp", scope, *path)
    end

    def scope
      test_number = ENV["TEST_ENV_NUMBER"]
      return "1" if test_number.nil?

      test_number.empty? ? "1" : test_number
    end

    def home(*path)
      tmp.join("home", *path)
    end

    def default_bundle_path(*path)
      if Bundler::VERSION.split(".").first.to_i < 3
        system_gem_path(*path)
      else
        bundled_app(*[".bundle", ENV.fetch("BUNDLER_SPEC_RUBY_ENGINE", Gem.ruby_engine), RbConfig::CONFIG["ruby_version"], *path].compact)
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
      bundled_app(*["vendor/bundle", Gem.ruby_engine, RbConfig::CONFIG["ruby_version"], path].compact)
    end

    def cached_gem(path)
      bundled_app("vendor/cache/#{path}.gem")
    end

    def base_system_gems
      tmp.join("gems/base")
    end

    def file_uri_for(path)
      protocol = "file://"
      root = Gem.win_platform? ? "/" : ""

      return protocol + "localhost" + root + path.to_s if RUBY_VERSION < "2.5"

      protocol + root + path.to_s
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

    def lib
      root.join("lib")
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

    def with_root_gemspec
      if ruby_core?
        root_gemspec = root.join("bundler.gemspec")
        spec = Gem::Specification.load(gemspec.to_s)
        spec.bindir = "libexec"
        File.open(root_gemspec.to_s, "w") {|f| f.write spec.to_ruby }
        yield(root_gemspec)
        FileUtils.rm(root_gemspec)
      else
        yield(gemspec)
      end
    end

    def ruby_core?
      # avoid to warnings
      @ruby_core ||= nil

      if @ruby_core.nil?
        @ruby_core = true & ENV["GEM_COMMAND"]
      else
        @ruby_core
      end
    end

    extend self
  end
end
