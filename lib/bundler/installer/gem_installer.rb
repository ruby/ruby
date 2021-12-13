# frozen_string_literal: true

module Bundler
  class GemInstaller
    attr_reader :spec, :standalone, :worker, :force, :installer

    def initialize(spec, installer, standalone = false, worker = 0, force = false)
      @spec = spec
      @installer = installer
      @standalone = standalone
      @worker = worker
      @force = force
    end

    def install_from_spec
      post_install_message = install
      Bundler.ui.debug "#{worker}:  #{spec.name} (#{spec.version}) from #{spec.loaded_from}"
      generate_executable_stubs
      return true, post_install_message
    rescue Bundler::InstallHookError, Bundler::SecurityError, Bundler::APIResponseMismatchError
      raise
    rescue Errno::ENOSPC
      return false, out_of_space_message
    rescue Bundler::BundlerError, Gem::InstallError, Bundler::APIResponseInvalidDependenciesError => e
      return false, specific_failure_message(e)
    end

    private

    def specific_failure_message(e)
      message = "#{e.class}: #{e.message}\n"
      message += "  " + e.backtrace.join("\n  ") + "\n\n"
      message = message.lines.first + Bundler.ui.add_color(message.lines.drop(1).join, :clear)
      message + Bundler.ui.add_color(failure_message, :red)
    end

    def failure_message
      install_error_message
    end

    def install_error_message
      "An error occurred while installing #{spec.name} (#{spec.version}), and Bundler cannot continue."
    end

    def spec_settings
      # Fetch the build settings, if there are any
      if settings = Bundler.settings["build.#{spec.name}"]
        require "shellwords"
        Shellwords.shellsplit(settings)
      end
    end

    def install
      spec.source.install(spec, :force => force, :ensure_builtin_gems_cached => standalone, :build_args => Array(spec_settings))
    end

    def out_of_space_message
      "#{install_error_message}\nYour disk is out of space. Free some space to be able to install your bundle."
    end

    def generate_executable_stubs
      return if Bundler.feature_flag.forget_cli_options?
      return if Bundler.settings[:inline]
      if Bundler.settings[:bin] && standalone
        installer.generate_standalone_bundler_executable_stubs(spec)
      elsif Bundler.settings[:bin]
        installer.generate_bundler_executable_stubs(spec, :force => true)
      end
    end
  end
end
