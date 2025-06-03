# frozen_string_literal: true

abort "RubyGems only supports Ruby 3.2 or higher" if RUBY_VERSION < "3.2.0"

require_relative "path"

$LOAD_PATH.unshift(Spec::Path.source_lib_dir.to_s)

module Spec
  module Rubygems
    extend self

    def gem_load(gem_name, bin_container)
      require_relative "switch_rubygems"

      gem_load_and_activate(gem_name, bin_container)
    end

    def gem_load_and_possibly_install(gem_name, bin_container)
      require_relative "switch_rubygems"

      gem_load_activate_and_possibly_install(gem_name, bin_container)
    end

    def gem_require(gem_name, entrypoint)
      gem_activate(gem_name)
      require entrypoint
    end

    def test_setup
      setup_test_paths

      require "fileutils"

      FileUtils.mkdir_p(Path.home)
      FileUtils.mkdir_p(Path.tmpdir)

      ENV["HOME"] = Path.home.to_s
      # Remove "RUBY_CODESIGN", which is used by mkmf-generated Makefile to
      # sign extension bundles on macOS, to avoid trying to find the specified key
      # from the fake $HOME/Library/Keychains directory.
      ENV.delete "RUBY_CODESIGN"
      ENV["TMPDIR"] = Path.tmpdir.to_s

      require "rubygems/user_interaction"
      Gem::DefaultUserInteraction.ui = Gem::SilentUI.new
    end

    def setup_test_paths
      ENV["BUNDLE_PATH"] = nil
      ENV["PATH"] = [Path.system_gem_path("bin"), ENV["PATH"]].join(File::PATH_SEPARATOR)
      ENV["PATH"] = [Path.bindir, ENV["PATH"]].join(File::PATH_SEPARATOR) if Path.ruby_core?
    end

    def install_test_deps
      dev_bundle("install", gemfile: test_gemfile, path: Path.base_system_gems.to_s)
      dev_bundle("install", gemfile: rubocop_gemfile, path: Path.rubocop_gems.to_s)
      dev_bundle("install", gemfile: standard_gemfile, path: Path.standard_gems.to_s)

      require_relative "helpers"
      Helpers.install_dev_bundler
    end

    def check_source_control_changes(success_message:, error_message:)
      require "open3"

      output, status = Open3.capture2e("git status --porcelain")

      if status.success? && output.empty?
        puts
        puts success_message
        puts
      else
        system("git diff")

        puts
        puts error_message
        puts

        exit(1)
      end
    end

    def dev_bundle(*args, gemfile: dev_gemfile, path: nil)
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

      require "shellwords"
      # We don't use `Open3` here because it does not work on JRuby + Windows
      output = `ruby #{File.expand_path("support/bundle.rb", Path.spec_dir)} #{args.shelljoin}`
      raise output unless $?.success?
      output
    ensure
      if path
        ENV["BUNDLE_PATH"] = old_path
      else
        ENV["BUNDLE_PATH__SYSTEM"] = old_path__system
      end

      ENV["BUNDLER_ORIG_BUNDLE_GEMFILE"] = old_orig_gemfile
      ENV["BUNDLE_GEMFILE"] = old_gemfile
    end

    private

    def gem_load_and_activate(gem_name, bin_container)
      gem_activate(gem_name)
      load Gem.bin_path(gem_name, bin_container)
    rescue Gem::LoadError => e
      abort "We couldn't activate #{gem_name} (#{e.requirement}). Run `gem install #{gem_name}:'#{e.requirement}'`"
    end

    def gem_load_activate_and_possibly_install(gem_name, bin_container)
      gem_activate_and_possibly_install(gem_name)
      load Gem.bin_path(gem_name, bin_container)
    end

    def gem_activate_and_possibly_install(gem_name)
      gem_activate(gem_name)
    rescue Gem::LoadError => e
      Gem.install(gem_name, e.requirement)
      retry
    end

    def gem_activate(gem_name)
      require_relative "activate"
      require "bundler"
      gem_requirement = Bundler::LockfileParser.new(File.read(dev_lockfile)).specs.find {|spec| spec.name == gem_name }.version
      gem gem_name, gem_requirement
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
