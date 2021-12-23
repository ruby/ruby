# frozen_string_literal: true

module Bundler
  #
  # This class handles installing and switching to the version of bundler needed
  # by an application.
  #
  class SelfManager
    def restart_with_locked_bundler_if_needed
      return unless needs_switching? && installed?

      restart_with_locked_bundler
    end

    def install_locked_bundler_and_restart_with_it_if_needed
      return unless needs_switching?

      Bundler.ui.info \
        "Bundler #{current_version} is running, but your lockfile was generated with #{lockfile_version}. " \
        "Installing Bundler #{lockfile_version} and restarting using that version."

      install_and_restart_with_locked_bundler
    end

    private

    def install_and_restart_with_locked_bundler
      bundler_dep = Gem::Dependency.new("bundler", lockfile_version)

      Gem.install(bundler_dep)
    rescue StandardError => e
      Bundler.ui.trace e
      Bundler.ui.warn "There was an error installing the locked bundler version (#{lockfile_version}), rerun with the `--verbose` flag for more details. Going on using bundler #{current_version}."
    else
      restart_with_locked_bundler
    end

    def restart_with_locked_bundler
      configured_gem_home = ENV["GEM_HOME"]
      configured_gem_path = ENV["GEM_PATH"]

      cmd = [$PROGRAM_NAME, *ARGV]
      cmd.unshift(Gem.ruby) unless File.executable?($PROGRAM_NAME)

      Bundler.with_original_env do
        Kernel.exec(
          { "GEM_HOME" => configured_gem_home, "GEM_PATH" => configured_gem_path, "BUNDLER_VERSION" => lockfile_version },
          *cmd
        )
      end
    end

    def needs_switching?
      ENV["BUNDLER_VERSION"].nil? &&
        Bundler.rubygems.supports_bundler_trampolining? &&
        SharedHelpers.in_bundle? &&
        lockfile_version &&
        !lockfile_version.end_with?(".dev") &&
        lockfile_version != current_version
    end

    def installed?
      Bundler.configure

      Bundler.rubygems.find_bundler(lockfile_version)
    end

    def current_version
      @current_version ||= Bundler::VERSION
    end

    def lockfile_version
      @lockfile_version ||= Bundler::LockfileParser.bundled_with
    end
  end
end
