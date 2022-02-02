# frozen_string_literal: true

require_relative "path"

$LOAD_PATH.unshift(Spec::Path.source_lib_dir.to_s)

module Spec
  module Rubygems
    extend self

    def dev_setup
      install_gems(dev_gemfile)
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
      Gem.clear_paths

      require "parallel"
      require "fileutils"

      install_test_deps

      (2..Parallel.processor_count).each do |n|
        source = Path.source_root.join("tmp", "1")
        destination = Path.source_root.join("tmp", n.to_s)

        FileUtils.rm_rf destination
        FileUtils.cp_r source, destination
      end
    end

    def setup_test_paths
      Gem.clear_paths

      ENV["BUNDLE_PATH"] = nil
      ENV["GEM_HOME"] = ENV["GEM_PATH"] = Path.base_system_gem_path.to_s
      ENV["PATH"] = [Path.system_gem_path.join("bin"), ENV["PATH"]].join(File::PATH_SEPARATOR)
      ENV["PATH"] = [Path.bindir, ENV["PATH"]].join(File::PATH_SEPARATOR) if Path.ruby_core?
    end

    def install_test_deps
      install_gems(test_gemfile, Path.base_system_gems.to_s)
      install_gems(rubocop_gemfile, Path.rubocop_gems.to_s)
      install_gems(standard_gemfile, Path.standard_gems.to_s)
    end

    def check_source_control_changes(success_message:, error_message:)
      require "open3"

      output, status = Open3.capture2e("git status --porcelain")

      if status.success? && output.empty?
        puts
        puts success_message
        puts
      else
        system("git status --porcelain")

        puts
        puts error_message
        puts

        exit(1)
      end
    end

    private

    def gem_load_and_activate(gem_name, bin_container)
      gem_activate(gem_name)
      load Gem.bin_path(gem_name, bin_container)
    rescue Gem::LoadError => e
      abort "We couldn't activate #{gem_name} (#{e.requirement}). Run `gem install #{gem_name}:'#{e.requirement}'`"
    end

    def gem_activate(gem_name)
      require "bundler"
      gem_requirement = Bundler::LockfileParser.new(File.read(dev_lockfile)).dependencies[gem_name]&.requirement
      gem gem_name, gem_requirement
    end

    def install_gems(gemfile, path = nil)
      old_gemfile = ENV["BUNDLE_GEMFILE"]
      old_orig_gemfile = ENV["BUNDLER_ORIG_BUNDLE_GEMFILE"]
      ENV["BUNDLE_GEMFILE"] = gemfile.to_s
      ENV["BUNDLER_ORIG_BUNDLE_GEMFILE"] = nil

      if path
        old_path = ENV["BUNDLE_PATH"]
        ENV["BUNDLE_PATH"] = path
      else
        old_path__system = ENV["BUNDLE_PATH__SYSTEM"]
        ENV["BUNDLE_PATH__SYSTEM"] = "true"
      end

      output = `#{Gem.ruby} #{File.expand_path("support/bundle.rb", Path.spec_dir)} install --verbose`
      raise "Error when installing gems in #{gemfile}: #{output}" unless $?.success?
    ensure
      if path
        ENV["BUNDLE_PATH"] = old_path
      else
        ENV["BUNDLE_PATH__SYSTEM"] = old_path__system
      end

      ENV["BUNDLER_ORIG_BUNDLE_GEMFILE"] = old_orig_gemfile
      ENV["BUNDLE_GEMFILE"] = old_gemfile
    end

    def test_gemfile
      Path.test_gemfile
    end

    def rubocop_gemfile
      Path.rubocop_gemfile
    end

    def standard_gemfile
      Path.standard_gemfile
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
