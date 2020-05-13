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

    def gem_cmd
      @gem_cmd ||= ruby_core? ? root.join("bin/gem") : "gem"
    end

    def gem_bin
      @gem_bin ||= ruby_core? ? ENV["GEM_COMMAND"] : "gem"
    end

    def spec_dir
      @spec_dir ||= root.join(ruby_core? ? "spec/bundler" : "spec")
    end

    def tracked_files
      @tracked_files ||= sys_exec(ruby_core? ? "git ls-files -z -- lib/bundler lib/bundler.rb spec/bundler man/bundler*" : "git ls-files -z", :dir => root).split("\x0")
    end

    def shipped_files
      @shipped_files ||= sys_exec(ruby_core? ? "git ls-files -z -- lib/bundler lib/bundler.rb man/bundler* libexec/bundle*" : "git ls-files -z -- lib man exe CHANGELOG.md LICENSE.md README.md bundler.gemspec", :dir => root).split("\x0")
    end

    def lib_tracked_files
      @lib_tracked_files ||= sys_exec(ruby_core? ? "git ls-files -z -- lib/bundler lib/bundler.rb" : "git ls-files -z -- lib", :dir => root).split("\x0")
    end

    def man_tracked_files
      @man_tracked_files ||= sys_exec(ruby_core? ? "git ls-files -z -- man/bundler*" : "git ls-files -z -- man", :dir => root).split("\x0")
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
      if Bundler.feature_flag.default_install_uses_path?
        local_gem_path(*path)
      else
        system_gem_path(*path)
      end
    end

    def bundled_app(*path)
      root = tmp.join("bundled_app")
      FileUtils.mkdir_p(root)
      root.join(*path)
    end

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

    def bundled_app_gemfile
      bundled_app("Gemfile")
    end

    def bundled_app_lock
      bundled_app("Gemfile.lock")
    end

    def base_system_gems
      tmp.join("gems/base")
    end

    def file_uri_for(path)
      protocol = "file://"
      root = Gem.win_platform? ? "/" : ""

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

    def local_gem_path(*path, base: bundled_app)
      base.join(*[".bundle", Gem.ruby_engine, RbConfig::CONFIG["ruby_version"], *path].compact)
    end

    def lib_path(*args)
      tmp("libs", *args)
    end

    def lib_dir
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

    def replace_version_file(version, dir: root)
      version_file = File.expand_path("lib/bundler/version.rb", dir)
      contents = File.read(version_file)
      contents.sub!(/(^\s+VERSION\s*=\s*)"#{Gem::Version::VERSION_PATTERN}"/, %(\\1"#{version}"))
      File.open(version_file, "w") {|f| f << contents }
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
