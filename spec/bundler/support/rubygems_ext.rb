# frozen_string_literal: true

require_relative "path"

$LOAD_PATH.unshift(Spec::Path.source_lib_dir.to_s)

module Spec
  module Rubygems
    extend self

    def dev_setup
      install_gems(dev_gemfile, dev_lockfile)
    end

    def gem_load(gem_name, bin_container)
      require_relative "switch_rubygems"

      gem_load_and_activate(gem_name, bin_container)
    end

    def gem_require(gem_name)
      gem_activate(gem_name)
      require gem_name
    end

    def test_setup
      setup_test_paths

      require "fileutils"

      FileUtils.mkdir_p(Path.home)
      FileUtils.mkdir_p(Path.tmpdir)

      ENV["HOME"] = Path.home.to_s
      ENV["TMPDIR"] = Path.tmpdir.to_s

      require "rubygems/user_interaction"
      Gem::DefaultUserInteraction.ui = Gem::SilentUI.new
    end

    def install_parallel_test_deps
      require "parallel"

      prev_env_test_number = ENV["TEST_ENV_NUMBER"]

      begin
        Parallel.processor_count.times do |n|
          ENV["TEST_ENV_NUMBER"] = (n + 1).to_s

          install_test_deps
        end
      ensure
        ENV["TEST_ENV_NUMBER"] = prev_env_test_number
      end
    end

    def setup_test_paths
      Gem.clear_paths

      ENV["BUNDLE_PATH"] = nil
      ENV["GEM_HOME"] = ENV["GEM_PATH"] = Path.base_system_gems.to_s
      ENV["PATH"] = [Path.system_gem_path.join("bin"), ENV["PATH"]].join(File::PATH_SEPARATOR)
      ENV["PATH"] = [Path.bindir, ENV["PATH"]].join(File::PATH_SEPARATOR) if Path.ruby_core?
    end

    def install_test_deps
      setup_test_paths

      workaround_loaded_specs_issue

      install_gems(test_gemfile, test_lockfile)
    end

    private

    # Some rubygems versions include loaded specs when loading gemspec stubs
    # from the file system. In this situation, that makes bundler incorrectly
    # assume that `rake` is already installed at `tmp/` because it's installed
    # globally, and makes it skip installing it to the proper location for our
    # tests. To workaround, we remove `rake` from the loaded specs when running
    # under those versions, so that `bundler` does the right thing.
    def workaround_loaded_specs_issue
      current_rubygems_version = Gem::Version.new(Gem::VERSION)

      Gem.loaded_specs.delete("rake") if current_rubygems_version >= Gem::Version.new("3.0.0.beta2") && current_rubygems_version < Gem::Version.new("3.2.0")
    end

    def gem_load_and_activate(gem_name, bin_container)
      gem_activate(gem_name)
      load Gem.bin_path(gem_name, bin_container)
    rescue Gem::LoadError => e
      abort "We couln't activate #{gem_name} (#{e.requirement}). Run `gem install #{gem_name}:'#{e.requirement}'`"
    end

    def gem_activate(gem_name)
      require "bundler"
      gem_requirement = Bundler::LockfileParser.new(File.read(dev_lockfile)).dependencies[gem_name]&.requirement
      gem gem_name, gem_requirement
    end

    def install_gems(gemfile, lockfile)
      old_gemfile = ENV["BUNDLE_GEMFILE"]
      ENV["BUNDLE_GEMFILE"] = gemfile.to_s
      require "bundler"
      definition = Bundler::Definition.build(gemfile, lockfile, nil)
      definition.validate_runtime!
      Bundler::Installer.install(Path.source_root, definition, :path => ENV["GEM_HOME"])
    ensure
      ENV["BUNDLE_GEMFILE"] = old_gemfile
    end

    def test_gemfile
      Path.test_gemfile
    end

    def test_lockfile
      lockfile_for(test_gemfile)
    end

    def dev_gemfile
      Path.dev_gemfile
    end

    def dev_lockfile
      lockfile_for(dev_gemfile)
    end

    def lockfile_for(gemfile)
      Pathname.new("#{gemfile.expand_path}.lock")
    end
  end
end
