# frozen_string_literal: true

module Bundler
  #
  # This class handles installing and switching to the version of bundler needed
  # by an application.
  #
  class SelfManager
    def restart_with_locked_bundler_if_needed
      restart_version = find_restart_version
      return unless restart_version && installed?(restart_version)

      restart_with(restart_version)
    end

    def install_locked_bundler_and_restart_with_it_if_needed
      restart_version = find_restart_version
      return unless restart_version

      if restart_version == lockfile_version
        Bundler.ui.info \
          "Bundler #{current_version} is running, but your lockfile was generated with #{lockfile_version}. " \
          "Installing Bundler #{lockfile_version} and restarting using that version."
      else
        Bundler.ui.info \
          "Bundler #{current_version} is running, but your configuration was #{restart_version}. " \
          "Installing Bundler #{restart_version} and restarting using that version."
      end

      install_and_restart_with(restart_version)
    end

    def update_bundler_and_restart_with_it_if_needed(target)
      spec = resolve_update_version_from(target)
      return unless spec

      version = spec.version

      Bundler.ui.info "Updating bundler to #{version}."

      install(spec) unless installed?(version)

      restart_with(version)
    end

    private

    def install_and_restart_with(version)
      requirement = Gem::Requirement.new(version)
      spec = find_latest_matching_spec(requirement)

      if spec.nil?
        Bundler.ui.warn "Your lockfile is locked to a version of bundler (#{lockfile_version}) that doesn't exist at https://rubygems.org/. Going on using #{current_version}"
        return
      end

      install(spec)
    rescue StandardError => e
      Bundler.ui.trace e
      Bundler.ui.warn "There was an error installing the locked bundler version (#{lockfile_version}), rerun with the `--verbose` flag for more details. Going on using bundler #{current_version}."
    else
      restart_with(version)
    end

    def install(spec)
      spec.source.install(spec)
    end

    def restart_with(version)
      configured_gem_home = ENV["GEM_HOME"]
      configured_gem_path = ENV["GEM_PATH"]

      # Bundler specs need some stuff to be required before Bundler starts
      # running, for example, for faking the compact index API. However, these
      # flags are lost when we reexec to a different version of Bundler. In the
      # future, we may be able to properly reconstruct the original Ruby
      # invocation (see https://bugs.ruby-lang.org/issues/6648), but for now
      # there's no way to do it, so we need to be explicit about how to re-exec.
      # This may be a feature end users request at some point, but maybe by that
      # time, we have builtin tools to do. So for now, we use an undocumented
      # ENV variable only for our specs.
      bundler_spec_original_cmd = ENV["BUNDLER_SPEC_ORIGINAL_CMD"]
      if bundler_spec_original_cmd
        require "shellwords"
        cmd = [*Shellwords.shellsplit(bundler_spec_original_cmd), *ARGV]
      else
        argv0 = File.exist?($PROGRAM_NAME) ? $PROGRAM_NAME : Process.argv0
        cmd = [argv0, *ARGV]
        cmd.unshift(Gem.ruby) unless File.executable?(argv0)
      end

      Bundler.with_original_env do
        Kernel.exec(
          { "GEM_HOME" => configured_gem_home, "GEM_PATH" => configured_gem_path, "BUNDLER_VERSION" => version.to_s },
          *cmd
        )
      end
    end

    def needs_switching?(restart_version)
      autoswitching_applies? &&
        released?(restart_version) &&
        !running?(restart_version)
    end

    def autoswitching_applies?
      ENV["BUNDLER_VERSION"].nil? &&
        ENV["BUNDLER_4_MODE"].nil? &&
        ruby_can_restart_with_same_arguments? &&
        lockfile_version
    end

    def resolve_update_version_from(target)
      requirement = Gem::Requirement.new(target)
      update_candidate = find_latest_matching_spec(requirement)

      if update_candidate.nil?
        raise InvalidOption, "The `bundle update --bundler` target version (#{target}) does not exist"
      end

      resolved_version = update_candidate.version
      needs_update = requirement.specific? ? !running?(resolved_version) : running_older_than?(resolved_version)

      return unless needs_update

      update_candidate
    end

    def local_specs
      @local_specs ||= Bundler::Source::Rubygems.new("allow_local" => true).specs.select {|spec| spec.name == "bundler" }
    end

    def remote_specs
      @remote_specs ||= begin
        source = Bundler::Source::Rubygems.new("remotes" => "https://rubygems.org")
        source.remote!
        source.add_dependency_names("bundler")
        source.specs.select(&:matches_current_metadata?)
      end
    end

    def find_latest_matching_spec(requirement)
      Bundler.configure
      local_result = find_latest_matching_spec_from_collection(local_specs, requirement)
      return local_result if local_result && requirement.specific?

      remote_result = find_latest_matching_spec_from_collection(remote_specs, requirement)
      return remote_result if local_result.nil?

      [local_result, remote_result].max
    end

    def find_latest_matching_spec_from_collection(specs, requirement)
      specs.sort.reverse_each.find {|spec| requirement.satisfied_by?(spec.version) }
    end

    def running?(version)
      version == current_version
    end

    def running_older_than?(version)
      current_version < version
    end

    def released?(version)
      !version.to_s.end_with?(".dev")
    end

    def ruby_can_restart_with_same_arguments?
      $PROGRAM_NAME != "-e"
    end

    def installed?(restart_version)
      Bundler.configure

      Bundler.rubygems.find_bundler(restart_version.to_s)
    end

    def current_version
      @current_version ||= Bundler.gem_version
    end

    def lockfile_version
      return @lockfile_version if defined?(@lockfile_version)

      parsed_version = Bundler::LockfileParser.bundled_with
      @lockfile_version = parsed_version ? Gem::Version.new(parsed_version) : nil
    rescue ArgumentError
      @lockfile_version = nil
    end

    def find_restart_version
      return unless SharedHelpers.in_bundle?

      configured_version = Bundler.settings[:version]
      return if configured_version == "system"

      restart_version = configured_version == "lockfile" ? lockfile_version : Gem::Version.new(configured_version)
      return unless needs_switching?(restart_version)

      restart_version
    end
  end
end
