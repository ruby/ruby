# frozen_string_literal: true

require "pathname"
require "rbconfig"

require_relative "env"

module Spec
  module Path
    include Spec::Env

    def source_root
      @source_root ||= Pathname.new(ruby_core? ? "../../.." : "../..").expand_path(__dir__)
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

    def loaded_gemspec
      @loaded_gemspec ||= Dir.chdir(source_root) { Gem::Specification.load(gemspec.to_s) }
    end

    def test_gemfile
      @test_gemfile ||= tool_dir.join("test_gems.rb")
    end

    def rubocop_gemfile
      @rubocop_gemfile ||= source_root.join(rubocop_gemfile_basename)
    end

    def standard_gemfile
      @standard_gemfile ||= source_root.join(standard_gemfile_basename)
    end

    def dev_gemfile
      @dev_gemfile ||= tool_dir.join("dev_gems.rb")
    end

    def dev_binstub
      @dev_binstub ||= bindir.join("bundle")
    end

    def bindir
      @bindir ||= source_root.join(ruby_core? ? "spec/bin" : "bin")
    end

    def exedir
      @exedir ||= source_root.join(ruby_core? ? "libexec" : "exe")
    end

    def installed_bindir
      @installed_bindir ||= system_gem_path("bin")
    end

    def gem_cmd
      @gem_cmd ||= ruby_core? ? source_root.join("bin/gem") : "gem"
    end

    def gem_bin
      @gem_bin ||= ENV["GEM_COMMAND"] || "gem"
    end

    def path
      env_path = ENV["PATH"]
      env_path = env_path.split(File::PATH_SEPARATOR).reject {|path| path == exedir.to_s }.join(File::PATH_SEPARATOR) if ruby_core?
      env_path
    end

    def spec_dir
      @spec_dir ||= source_root.join(ruby_core? ? "spec/bundler" : "spec")
    end

    def man_dir
      @man_dir ||= lib_dir.join("bundler/man")
    end

    def hax
      @hax ||= spec_dir.join("support/hax.rb")
    end

    def tracked_files
      @tracked_files ||= git_ls_files(tracked_files_glob)
    end

    def shipped_files
      @shipped_files ||= if ruby_core_tarball?
        loaded_gemspec.files.map {|f| f.gsub(%r{^exe/}, "libexec/") }
      elsif ruby_core?
        tracked_files
      else
        loaded_gemspec.files
      end
    end

    def lib_tracked_files
      @lib_tracked_files ||= git_ls_files(lib_tracked_files_glob)
    end

    def man_tracked_files
      @man_tracked_files ||= git_ls_files(man_tracked_files_glob)
    end

    def tmp(*path)
      tmp_root.join("#{test_env_version}.#{scope}").join(*path)
    end

    def tmp_root
      source_root.join("tmp")
    end

    # Bump this version whenever you make a breaking change to the spec setup
    # that requires regenerating tmp/.

    def test_env_version
      2
    end

    def scope
      test_number = ENV["TEST_ENV_NUMBER"]
      return "1" if test_number.nil?

      test_number.empty? ? "1" : test_number
    end

    def home(*path)
      tmp("home", *path)
    end

    def default_bundle_path(*path)
      system_gem_path(*path)
    end

    def default_cache_path(*path)
      default_bundle_path("cache/bundler", *path)
    end

    def compact_index_cache_path
      home(".bundle/cache/compact_index")
    end

    def bundled_app(*path)
      root = tmp("bundled_app")
      FileUtils.mkdir_p(root)
      root.join(*path)
    end

    def bundled_app2(*path)
      root = tmp("bundled_app2")
      FileUtils.mkdir_p(root)
      root.join(*path)
    end

    def vendored_gems(path = nil)
      scoped_gem_path(bundled_app("vendor/bundle")).join(*[path].compact)
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

    def scoped_base_system_gem_path
      scoped_gem_path(base_system_gem_path)
    end

    def base_system_gem_path
      tmp_root.join("gems/base")
    end

    def rubocop_gem_path
      tmp_root.join("gems/rubocop")
    end

    def standard_gem_path
      tmp_root.join("gems/standard")
    end

    def file_uri_for(path)
      protocol = "file://"
      root = Gem.win_platform? ? "/" : ""

      protocol + root + path.to_s
    end

    def gem_repo1(*args)
      gem_path("remote1", *args)
    end

    def gem_repo_missing(*args)
      gem_path("missing", *args)
    end

    def gem_repo2(*args)
      gem_path("remote2", *args)
    end

    def gem_repo3(*args)
      gem_path("remote3", *args)
    end

    def gem_repo4(*args)
      gem_path("remote4", *args)
    end

    def security_repo(*args)
      gem_path("security_repo", *args)
    end

    def system_gem_path(*path)
      gem_path("system", *path)
    end

    def pristine_system_gem_path
      tmp_root.join("gems/pristine_system")
    end

    def local_gem_path(*path, base: bundled_app)
      scoped_gem_path(base.join(".bundle")).join(*path)
    end

    def scoped_gem_path(base)
      base.join(Gem.ruby_engine, RbConfig::CONFIG["ruby_version"])
    end

    def gem_path(*args)
      tmp("gems", *args)
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
      contents.sub!(/(^\s+VERSION\s*=\s*).*$/, %(\\1"#{version}"))
      File.open(version_file, "w") {|f| f << contents }
    end

    def replace_required_ruby_version(version, dir:)
      gemspec_file = File.expand_path("bundler.gemspec", dir)
      contents = File.read(gemspec_file)
      contents.sub!(/(^\s+s\.required_ruby_version\s*=\s*)"[^"]+"/, %(\\1"#{version}"))
      File.open(gemspec_file, "w") {|f| f << contents }
    end

    def replace_changelog(version, dir:)
      changelog = File.expand_path("CHANGELOG.md", dir)
      contents = File.readlines(changelog)
      contents = [contents[0], contents[1], "## #{version} (2100-01-01)\n", *contents[3..-1]].join
      File.open(changelog, "w") {|f| f << contents }
    end

    def git_root
      ruby_core? ? source_root : source_root.parent
    end

    def rake_path
      find_base_path("rake")
    end

    def rake_version
      File.basename(rake_path).delete_prefix("rake-").delete_suffix(".gem")
    end

    def sinatra_dependency_paths
      deps = %w[
        mustermann
        rack
        tilt
        sinatra
        ruby2_keywords
        base64
        logger
        cgi
      ]
      Dir[scoped_base_system_gem_path.join("gems/{#{deps.join(",")}}-*/lib")].map(&:to_s)
    end

    private

    def find_base_path(name)
      Dir["#{scoped_base_system_gem_path}/**/#{name}-*.gem"].first
    end

    def git_ls_files(glob)
      skip "Not running on a git context, since running tests from a tarball" if ruby_core_tarball?

      git("ls-files -z -- #{glob}", source_root).split("\x0")
    end

    def tracked_files_glob
      ruby_core? ? "libexec/bundle* lib/bundler lib/bundler.rb spec/bundler man/bundle*" : "lib exe spec CHANGELOG.md LICENSE.md README.md bundler.gemspec"
    end

    def lib_tracked_files_glob
      ruby_core? ? "lib/bundler lib/bundler.rb" : "lib"
    end

    def man_tracked_files_glob
      "lib/bundler/man/bundle*.1.ronn lib/bundler/man/gemfile*.5.ronn"
    end

    def ruby_core_tarball?
      !git_root.join(".git").directory?
    end

    def rubocop_gemfile_basename
      tool_dir.join("rubocop_gems.rb")
    end

    def standard_gemfile_basename
      tool_dir.join("standard_gems.rb")
    end

    def tool_dir
      ruby_core? ? source_root.join("tool/bundler") : source_root.join("../tool/bundler")
    end

    def templates_dir
      lib_dir.join("bundler", "templates")
    end

    extend self
  end
end
