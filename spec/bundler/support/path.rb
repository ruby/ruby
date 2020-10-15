# frozen_string_literal: true

require "pathname"
require "rbconfig"

module Spec
  module Path
    def source_root
      @source_root ||= Pathname.new(ruby_core? ? "../../../.." : "../../..").expand_path(__FILE__)
    end

    def root
      @root ||= system_gem_path("gems/bundler-#{Bundler::VERSION}")
    end

    def gemspec
      @gemspec ||= source_root.join(relative_gemspec)
    end

    def relative_gemspec
      @relative_gemspec ||= ruby_core? ? "lib/bundler/bundler.gemspec" : "bundler.gemspec"
    end

    def gemspec_dir
      @gemspec_dir ||= gemspec.parent
    end

    def loaded_gemspec
      @loaded_gemspec ||= Gem::Specification.load(gemspec.to_s)
    end

    def test_gemfile
      @test_gemfile ||= source_root.join(ruby_core? ? "tool/bundler/test_gems.rb" : "test_gems.rb")
    end

    def dev_gemfile
      @dev_gemfile ||= git_root.join("dev_gems.rb")
    end

    def bindir
      @bindir ||= source_root.join(ruby_core? ? "libexec" : "exe")
    end

    def installed_bindir
      @installed_bindir ||= system_gem_path("bin")
    end

    def gem_cmd
      @gem_cmd ||= ruby_core? ? source_root.join("bin/gem") : "gem"
    end

    def gem_bin
      @gem_bin ||= ruby_core? ? ENV["GEM_COMMAND"] : "gem"
    end

    def path
      env_path = ENV["PATH"]
      env_path = env_path.split(File::PATH_SEPARATOR).reject {|path| path == bindir.to_s }.join(File::PATH_SEPARATOR) if ruby_core?
      env_path
    end

    def spec_dir
      @spec_dir ||= source_root.join(ruby_core? ? "spec/bundler" : "spec")
    end

    def tracked_files
      @tracked_files ||= git_ls_files(tracked_files_glob)
    end

    def shipped_files
      @shipped_files ||= loaded_gemspec.files
    end

    def lib_tracked_files
      @lib_tracked_files ||= git_ls_files(lib_tracked_files_glob)
    end

    def man_tracked_files
      @man_tracked_files ||= git_ls_files(man_tracked_files_glob)
    end

    def tmp(*path)
      source_root.join("tmp", scope, *path)
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

    def pristine_system_gem_path
      tmp("gems/base_system")
    end

    def local_gem_path(*path, base: bundled_app)
      base.join(*[".bundle", Gem.ruby_engine, RbConfig::CONFIG["ruby_version"], *path].compact)
    end

    def lib_path(*args)
      tmp("libs", *args)
    end

    def source_lib_dir
      source_root.join("lib")
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

    def replace_version_file(version, dir: source_root)
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

    private

    def git_ls_files(glob)
      skip "Not running on a git context, since running tests from a tarball" if ruby_core_tarball?

      sys_exec("git ls-files -z -- #{glob}", :dir => source_root).split("\x0")
    end

    def tracked_files_glob
      ruby_core? ? "lib/bundler lib/bundler.rb spec/bundler man/bundle*" : ""
    end

    def lib_tracked_files_glob
      ruby_core? ? "lib/bundler lib/bundler.rb" : "lib"
    end

    def man_tracked_files_glob
      ruby_core? ? "man/bundle* man/gemfile*" : "man"
    end

    def git_root
      ruby_core? ? source_root : source_root.parent
    end

    def ruby_core_tarball?
      !git_root.join(".git").directory?
    end

    extend self
  end
end
