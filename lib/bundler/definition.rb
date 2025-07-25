# frozen_string_literal: true

require_relative "lockfile_parser"

module Bundler
  class Definition
    class << self
      # Do not create or modify a lockfile (Makes #lock a noop)
      attr_accessor :no_lock
    end

    attr_reader(
      :dependencies,
      :locked_checksums,
      :locked_deps,
      :locked_gems,
      :platforms,
      :ruby_version,
      :lockfile,
      :gemfiles,
      :sources
    )

    # Given a gemfile and lockfile creates a Bundler definition
    #
    # @param gemfile [Pathname] Path to Gemfile
    # @param lockfile [Pathname,nil] Path to Gemfile.lock
    # @param unlock [Hash, Boolean, nil] Gems that have been requested
    #   to be updated or true if all gems should be updated
    # @return [Bundler::Definition]
    def self.build(gemfile, lockfile, unlock)
      unlock ||= {}
      gemfile = Pathname.new(gemfile).expand_path

      raise GemfileNotFound, "#{gemfile} not found" unless gemfile.file?

      Dsl.evaluate(gemfile, lockfile, unlock)
    end

    #
    # How does the new system work?
    #
    # * Load information from Gemfile and Lockfile
    # * Invalidate stale locked specs
    #  * All specs from stale source are stale
    #  * All specs that are reachable only through a stale
    #    dependency are stale.
    # * If all fresh dependencies are satisfied by the locked
    #  specs, then we can try to resolve locally.
    #
    # @param lockfile [Pathname] Path to Gemfile.lock
    # @param dependencies [Array(Bundler::Dependency)] array of dependencies from Gemfile
    # @param sources [Bundler::SourceList]
    # @param unlock [Hash, Boolean, nil] Gems that have been requested
    #   to be updated or true if all gems should be updated
    # @param ruby_version [Bundler::RubyVersion, nil] Requested Ruby Version
    # @param optional_groups [Array(String)] A list of optional groups
    def initialize(lockfile, dependencies, sources, unlock, ruby_version = nil, optional_groups = [], gemfiles = [])
      unlock ||= {}

      if unlock == true
        @unlocking_all = true
        strict = false
        @unlocking_bundler = false
        @unlocking = unlock
        @sources_to_unlock = []
        @unlocking_ruby = false
        @explicit_unlocks = []
        conservative = false
      else
        @unlocking_all = false
        strict = unlock.delete(:strict)
        @unlocking_bundler = unlock.delete(:bundler)
        @unlocking = unlock.any? {|_k, v| !Array(v).empty? }
        @sources_to_unlock = unlock.delete(:sources) || []
        @unlocking_ruby = unlock.delete(:ruby)
        @explicit_unlocks = unlock.delete(:gems) || []
        conservative = unlock.delete(:conservative)
      end

      @dependencies    = dependencies
      @sources         = sources
      @optional_groups = optional_groups
      @prefer_local    = false
      @specs           = nil
      @ruby_version    = ruby_version
      @gemfiles        = gemfiles

      @lockfile               = lockfile
      @lockfile_contents      = String.new

      @locked_bundler_version = nil
      @resolved_bundler_version = nil

      @locked_ruby_version = nil
      @new_platforms = []
      @removed_platforms = []
      @originally_invalid_platforms = []

      if lockfile_exists?
        @lockfile_contents = Bundler.read_file(lockfile)
        @locked_gems = LockfileParser.new(@lockfile_contents, strict: strict)
        @locked_platforms = @locked_gems.platforms
        @most_specific_locked_platform = @locked_gems.most_specific_locked_platform
        @platforms = @locked_platforms.dup
        @locked_bundler_version = @locked_gems.bundler_version
        @locked_ruby_version = @locked_gems.ruby_version
        @locked_deps = @locked_gems.dependencies
        @originally_locked_specs = SpecSet.new(@locked_gems.specs)
        @locked_checksums = @locked_gems.checksums

        if @unlocking_all
          @locked_specs   = SpecSet.new([])
          @locked_sources = []
        else
          @locked_specs   = @originally_locked_specs
          @locked_sources = @locked_gems.sources
        end
      else
        @locked_gems = nil
        @locked_platforms = []
        @most_specific_locked_platform = nil
        @platforms      = []
        @locked_deps    = {}
        @locked_specs   = SpecSet.new([])
        @originally_locked_specs = @locked_specs
        @locked_sources = []
        @locked_checksums = Bundler.feature_flag.lockfile_checksums?
      end

      locked_gem_sources = @locked_sources.select {|s| s.is_a?(Source::Rubygems) }
      @multisource_allowed = locked_gem_sources.size == 1 && locked_gem_sources.first.multiple_remotes? && Bundler.frozen_bundle?

      if @multisource_allowed
        unless sources.aggregate_global_source?
          msg = "Your lockfile contains a single rubygems source section with multiple remotes, which is insecure. Make sure you run `bundle install` in non frozen mode and commit the result to make your lockfile secure."

          Bundler::SharedHelpers.major_deprecation 2, msg
        end

        @sources.merged_gem_lockfile_sections!(locked_gem_sources.first)
      end

      @unlocking_ruby ||= if @ruby_version && locked_ruby_version_object
        @ruby_version.diff(locked_ruby_version_object)
      end
      @unlocking ||= @unlocking_ruby ||= (!@locked_ruby_version ^ !@ruby_version)

      @current_platform_missing = add_current_platform unless Bundler.frozen_bundle?

      @source_changes = converge_sources
      @path_changes = converge_paths

      if conservative
        @gems_to_unlock = @explicit_unlocks.any? ? @explicit_unlocks : @dependencies.map(&:name)
      else
        eager_unlock = @explicit_unlocks.map {|name| Dependency.new(name, ">= 0") }
        @gems_to_unlock = @locked_specs.for(eager_unlock, platforms).map(&:name).uniq
      end

      @dependency_changes = converge_dependencies
      @local_changes = converge_locals

      check_lockfile
    end

    def gem_version_promoter
      @gem_version_promoter ||= GemVersionPromoter.new
    end

    def check!
      # If dependencies have changed, we need to resolve remotely. Otherwise,
      # since we'll be resolving with a single local source, we may end up
      # locking gems under the wrong source in the lockfile, and missing lockfile
      # checksums
      resolve_remotely! if @dependency_changes

      # Now do a local only resolve, to verify if any gems are missing locally
      sources.local_only!
      resolve
    end

    #
    # Setup sources according to the given options and the state of the
    # definition.
    #
    # @return [Boolean] Whether fetching remote information will be necessary or not
    #
    def setup_domain!(options = {})
      prefer_local! if options[:"prefer-local"]

      if options[:add_checksums] || (!options[:local] && install_needed?)
        remotely!
        true
      else
        Bundler.settings.set_command_option(:jobs, 1) unless install_needed? # to avoid the overhead of Bundler::Worker
        with_cache!
        false
      end
    end

    def resolve_with_cache!
      with_cache!

      resolve
    end

    def with_cache!
      sources.local!
      sources.cached!
    end

    def resolve_remotely!
      remotely!

      resolve
    end

    def remotely!
      sources.cached!
      sources.remote!
    end

    def prefer_local!
      @prefer_local = true

      sources.prefer_local!
    end

    # For given dependency list returns a SpecSet with Gemspec of all the required
    # dependencies.
    #  1. The method first resolves the dependencies specified in Gemfile
    #  2. After that it tries and fetches gemspec of resolved dependencies
    #
    # @return [Bundler::SpecSet]
    def specs
      @specs ||= materialize(requested_dependencies)
    end

    def new_specs
      specs - @locked_specs
    end

    def removed_specs
      @locked_specs - specs
    end

    def missing_specs
      resolve.missing_specs_for(requested_dependencies)
    end

    def missing_specs?
      missing = missing_specs
      return false if missing.empty?
      Bundler.ui.debug "The definition is missing #{missing.map(&:full_name)}"
      true
    rescue BundlerError => e
      @resolve = nil
      @resolver = nil
      @resolution_base = nil
      @source_requirements = nil
      @specs = nil

      Bundler.ui.debug "The definition is missing dependencies, failed to resolve & materialize locally (#{e})"
      true
    end

    def requested_specs
      specs_for(requested_groups)
    end

    def requested_dependencies
      dependencies_for(requested_groups)
    end

    def current_dependencies
      filter_relevant(dependencies)
    end

    def current_locked_dependencies
      filter_relevant(locked_dependencies)
    end

    def filter_relevant(dependencies)
      platforms_array = [Bundler.generic_local_platform].freeze
      dependencies.select do |d|
        d.should_include? && !d.gem_platforms(platforms_array).empty?
      end
    end

    def locked_dependencies
      @locked_deps.values
    end

    def new_deps
      @new_deps ||= @dependencies - locked_dependencies
    end

    def deleted_deps
      @deleted_deps ||= locked_dependencies - @dependencies
    end

    def specs_for(groups)
      return specs if groups.empty?
      deps = dependencies_for(groups)
      materialize(deps)
    end

    def dependencies_for(groups)
      groups.map!(&:to_sym)
      deps = current_dependencies # always returns a new array
      deps.select! do |d|
        d.groups.intersect?(groups)
      end
      deps
    end

    # Resolve all the dependencies specified in Gemfile. It ensures that
    # dependencies that have been already resolved via locked file and are fresh
    # are reused when resolving dependencies
    #
    # @return [SpecSet] resolved dependencies
    def resolve
      @resolve ||= if Bundler.frozen_bundle?
        Bundler.ui.debug "Frozen, using resolution from the lockfile"
        @locked_specs
      elsif no_resolve_needed?
        if deleted_deps.any?
          Bundler.ui.debug "Some dependencies were deleted, using a subset of the resolution from the lockfile"
          SpecSet.new(filter_specs(@locked_specs, @dependencies - deleted_deps))
        else
          Bundler.ui.debug "Found no changes, using resolution from the lockfile"
          if @removed_platforms.any? || @locked_gems.may_include_redundant_platform_specific_gems?
            SpecSet.new(filter_specs(@locked_specs, @dependencies))
          else
            @locked_specs
          end
        end
      else
        Bundler.ui.debug resolve_needed_reason

        start_resolution
      end
    end

    def spec_git_paths
      sources.git_sources.filter_map {|s| File.realpath(s.path) if File.exist?(s.path) }
    end

    def groups
      dependencies.flat_map(&:groups).uniq
    end

    def lock(file_or_preserve_unknown_sections = false, preserve_unknown_sections_or_unused = false)
      if [true, false, nil].include?(file_or_preserve_unknown_sections)
        target_lockfile = lockfile
        preserve_unknown_sections = file_or_preserve_unknown_sections
      else
        target_lockfile = file_or_preserve_unknown_sections
        preserve_unknown_sections = preserve_unknown_sections_or_unused

        suggestion = if target_lockfile == lockfile
          "To fix this warning, remove it from the `Definition#lock` call."
        else
          "Instead, instantiate a new definition passing `#{target_lockfile}`, and call `lock` without a file argument on that definition"
        end

        msg = "`Definition#lock` was passed a target file argument. #{suggestion}"

        Bundler::SharedHelpers.major_deprecation 2, msg
      end

      write_lock(target_lockfile, preserve_unknown_sections)
    end

    def locked_ruby_version
      return unless ruby_version
      if @unlocking_ruby || !@locked_ruby_version
        Bundler::RubyVersion.system
      else
        @locked_ruby_version
      end
    end

    def locked_ruby_version_object
      return unless @locked_ruby_version
      @locked_ruby_version_object ||= begin
        unless version = RubyVersion.from_string(@locked_ruby_version)
          raise LockfileError, "The Ruby version #{@locked_ruby_version} from " \
            "#{@lockfile} could not be parsed. " \
            "Try running bundle update --ruby to resolve this."
        end
        version
      end
    end

    def bundler_version_to_lock
      @resolved_bundler_version || Bundler.gem_version
    end

    def to_lock
      require_relative "lockfile_generator"
      LockfileGenerator.generate(self)
    end

    def ensure_equivalent_gemfile_and_lockfile(explicit_flag = false)
      return unless Bundler.frozen_bundle?

      raise ProductionError, "Frozen mode is set, but there's no lockfile" unless lockfile_exists?

      msg = lockfile_changes_summary("frozen mode is set")
      return unless msg

      unless explicit_flag
        suggested_command = unless Bundler.settings.locations("frozen").keys.include?(:env)
          "bundle config set frozen false"
        end
        msg << "\n\nIf this is a development machine, remove the #{SharedHelpers.relative_lockfile_path} " \
               "freeze by running `#{suggested_command}`." if suggested_command
      end

      raise ProductionError, msg
    end

    def validate_runtime!
      validate_ruby!
      validate_platforms!
    end

    def validate_ruby!
      return unless ruby_version

      if diff = ruby_version.diff(Bundler::RubyVersion.system)
        problem, expected, actual = diff

        msg = case problem
              when :engine
                "Your Ruby engine is #{actual}, but your Gemfile specified #{expected}"
              when :version
                "Your Ruby version is #{actual}, but your Gemfile specified #{expected}"
              when :engine_version
                "Your #{Bundler::RubyVersion.system.engine} version is #{actual}, but your Gemfile specified #{ruby_version.engine} #{expected}"
              when :patchlevel
                if !expected.is_a?(String)
                  "The Ruby patchlevel in your Gemfile must be a string"
                else
                  "Your Ruby patchlevel is #{actual}, but your Gemfile specified #{expected}"
                end
        end

        raise RubyVersionMismatch, msg
      end
    end

    def validate_platforms!
      return if current_platform_locked? || @platforms.include?(Gem::Platform::RUBY)

      raise ProductionError, "Your bundle only supports platforms #{@platforms.map(&:to_s)} " \
        "but your local platform is #{Bundler.local_platform}. " \
        "Add the current platform to the lockfile with\n`bundle lock --add-platform #{Bundler.local_platform}` and try again."
    end

    def normalize_platforms
      resolve.normalize_platforms!(current_dependencies, platforms)

      @resolve = SpecSet.new(resolve.for(current_dependencies, @platforms))
    end

    def add_platform(platform)
      return if @platforms.include?(platform)

      @new_platforms << platform
      @platforms << platform
    end

    def remove_platform(platform)
      raise InvalidOption, "Unable to remove the platform `#{platform}` since the only platforms are #{@platforms.join ", "}" unless @platforms.include?(platform)

      @removed_platforms << platform
      @platforms.delete(platform)
    end

    def nothing_changed?
      !something_changed?
    end

    def no_resolve_needed?
      !resolve_needed?
    end

    def unlocking?
      @unlocking
    end

    attr_writer :source_requirements

    def add_checksums
      @locked_checksums = true

      setup_domain!(add_checksums: true)

      specs # force materialization to real specifications, so that checksums are fetched
    end

    private

    def lockfile_changes_summary(update_refused_reason)
      added =   []
      deleted = []
      changed = []

      added.concat @new_platforms.map {|p| "* platform: #{p}" }
      deleted.concat @removed_platforms.map {|p| "* platform: #{p}" }

      added.concat new_deps.map {|d| "* #{pretty_dep(d)}" } if new_deps.any?
      deleted.concat deleted_deps.map {|d| "* #{pretty_dep(d)}" } if deleted_deps.any?

      both_sources = Hash.new {|h, k| h[k] = [] }
      current_dependencies.each {|d| both_sources[d.name][0] = d }
      current_locked_dependencies.each {|d| both_sources[d.name][1] = d }

      both_sources.each do |name, (dep, lock_dep)|
        next if dep.nil? || lock_dep.nil?

        gemfile_source = dep.source || default_source
        lock_source = lock_dep.source || default_source
        next if lock_source.include?(gemfile_source)

        gemfile_source_name = dep.source ? gemfile_source.to_gemfile : "no specified source"
        lockfile_source_name = lock_dep.source ? lock_source.to_gemfile : "no specified source"
        changed << "* #{name} from `#{lockfile_source_name}` to `#{gemfile_source_name}`"
      end

      return unless added.any? || deleted.any? || changed.any? || resolve_needed?

      msg = String.new("#{change_reason.capitalize.strip}, but ")
      msg << "the lockfile " unless msg.start_with?("Your lockfile")
      msg << "can't be updated because #{update_refused_reason}"
      msg << "\n\nYou have added to the Gemfile:\n" << added.join("\n") if added.any?
      msg << "\n\nYou have deleted from the Gemfile:\n" << deleted.join("\n") if deleted.any?
      msg << "\n\nYou have changed in the Gemfile:\n" << changed.join("\n") if changed.any?
      msg << "\n\nRun `bundle install` elsewhere and add the updated #{SharedHelpers.relative_lockfile_path} to version control.\n" unless unlocking?
      msg
    end

    def install_needed?
      resolve_needed? || missing_specs?
    end

    def something_changed?
      return true unless lockfile_exists?

      @source_changes ||
        @dependency_changes ||
        @current_platform_missing ||
        @new_platforms.any? ||
        @path_changes ||
        @local_changes ||
        @missing_lockfile_dep ||
        @unlocking_bundler ||
        @locked_spec_with_missing_checksums ||
        @locked_spec_with_missing_deps ||
        @locked_spec_with_invalid_deps
    end

    def resolve_needed?
      unlocking? || something_changed?
    end

    def should_add_extra_platforms?
      !lockfile_exists? && Bundler::MatchPlatform.generic_local_platform_is_ruby? && !Bundler.settings[:force_ruby_platform]
    end

    def lockfile_exists?
      lockfile && File.exist?(lockfile)
    end

    def write_lock(file, preserve_unknown_sections)
      return if Definition.no_lock || file.nil?

      contents = to_lock

      # Convert to \r\n if the existing lock has them
      # i.e., Windows with `git config core.autocrlf=true`
      contents.gsub!(/\n/, "\r\n") if @lockfile_contents.match?("\r\n")

      if @locked_bundler_version
        locked_major = @locked_bundler_version.segments.first
        current_major = bundler_version_to_lock.segments.first

        updating_major = locked_major < current_major
      end

      preserve_unknown_sections ||= !updating_major && (Bundler.frozen_bundle? || !(unlocking? || @unlocking_bundler))

      if File.exist?(file) && lockfiles_equal?(@lockfile_contents, contents, preserve_unknown_sections)
        return if Bundler.frozen_bundle?
        SharedHelpers.filesystem_access(file) { FileUtils.touch(file) }
        return
      end

      if Bundler.frozen_bundle?
        Bundler.ui.error "Cannot write a changed lockfile while frozen."
        return
      end

      begin
        SharedHelpers.filesystem_access(file) do |p|
          File.open(p, "wb") {|f| f.puts(contents) }
        end
      rescue ReadOnlyFileSystemError
        raise ProductionError, lockfile_changes_summary("file system is read-only")
      end
    end

    def resolver
      @resolver ||= Resolver.new(resolution_base, gem_version_promoter, @most_specific_locked_platform)
    end

    def expanded_dependencies
      dependencies_with_bundler + metadata_dependencies
    end

    def dependencies_with_bundler
      return dependencies unless @unlocking_bundler
      return dependencies if dependencies.any? {|d| d.name == "bundler" }

      [Dependency.new("bundler", @unlocking_bundler)] + dependencies
    end

    def resolution_base
      @resolution_base ||= begin
        last_resolve = converge_locked_specs
        remove_invalid_platforms!
        new_resolution_platforms = @current_platform_missing ? @new_platforms + [Bundler.local_platform] : @new_platforms
        base = Resolver::Base.new(source_requirements, expanded_dependencies, last_resolve, @platforms, locked_specs: @originally_locked_specs, unlock: @unlocking_all || @gems_to_unlock, prerelease: gem_version_promoter.pre?, prefer_local: @prefer_local, new_platforms: new_resolution_platforms)
        base = additional_base_requirements_to_prevent_downgrades(base)
        base = additional_base_requirements_to_force_updates(base)
        base
      end
    end

    def filter_specs(specs, deps, skips: [])
      SpecSet.new(specs).for(deps, platforms, skips: skips)
    end

    def materialize(dependencies)
      specs = begin
        resolve.materialize(dependencies)
      rescue IncorrectLockfileDependencies => e
        raise if Bundler.frozen_bundle?

        reresolve_without([e.spec])
        retry
      end

      missing_specs = resolve.missing_specs

      if missing_specs.any?
        missing_specs.each do |s|
          locked_gem = @locked_specs[s.name].last
          next if locked_gem.nil? || locked_gem.version != s.version || sources.local_mode?

          message = if sources.implicit_global_source?
            "Because your Gemfile specifies no global remote source, your bundle is locked to " \
            "#{locked_gem} from #{locked_gem.source}. However, #{locked_gem} is not installed. You'll " \
            "need to either add a global remote source to your Gemfile or make sure #{locked_gem} is " \
            "available locally before rerunning Bundler."
          else
            "Your bundle is locked to #{locked_gem} from #{locked_gem.source}, but that version can " \
            "no longer be found in that source. That means the author of #{locked_gem} has removed it. " \
            "You'll need to update your bundle to a version other than #{locked_gem} that hasn't been " \
            "removed in order to install."
          end

          raise GemNotFound, message
        end

        missing_specs_list = missing_specs.group_by(&:source).map do |source, missing_specs_for_source|
          "#{missing_specs_for_source.map(&:full_name).join(", ")} in #{source}"
        end

        raise GemNotFound, "Could not find #{missing_specs_list.join(" nor ")}"
      end

      partially_missing_specs = resolve.partially_missing_specs

      if partially_missing_specs.any? && !sources.local_mode?
        Bundler.ui.warn "Some locked specs have possibly been yanked (#{partially_missing_specs.map(&:full_name).join(", ")}). Ignoring them..."

        resolve.delete(partially_missing_specs)
      end

      incomplete_specs = resolve.incomplete_specs
      loop do
        break if incomplete_specs.empty?

        Bundler.ui.debug("The lockfile does not have all gems needed for the current platform though, Bundler will still re-resolve dependencies")
        sources.remote!
        reresolve_without(incomplete_specs)
        specs = resolve.materialize(dependencies)

        still_incomplete_specs = resolve.incomplete_specs

        if still_incomplete_specs == incomplete_specs
          resolver.raise_incomplete! incomplete_specs
        end

        incomplete_specs = still_incomplete_specs
      end

      insecurely_materialized_specs = resolve.insecurely_materialized_specs

      if insecurely_materialized_specs.any?
        Bundler.ui.warn "The following platform specific gems are getting installed, yet the lockfile includes only their generic ruby version:\n" \
                        " * #{insecurely_materialized_specs.map(&:full_name).join("\n * ")}\n" \
                        "Please run `bundle lock --normalize-platforms` and commit the resulting lockfile.\n" \
                        "Alternatively, you may run `bundle lock --add-platform <list-of-platforms-that-you-want-to-support>`"
      end

      bundler = sources.metadata_source.specs.search(["bundler", Bundler.gem_version]).last
      specs["bundler"] = bundler

      specs
    end

    def reresolve_without(incomplete_specs)
      resolution_base.delete(incomplete_specs)
      @resolve = start_resolution
    end

    def start_resolution
      local_platform_needed_for_resolvability = @most_specific_non_local_locked_platform && !@platforms.include?(Bundler.local_platform)
      @platforms << Bundler.local_platform if local_platform_needed_for_resolvability

      result = SpecSet.new(resolver.start)

      @resolved_bundler_version = result.find {|spec| spec.name == "bundler" }&.version

      @new_platforms.each do |platform|
        incomplete_specs = result.incomplete_specs_for_platform(current_dependencies, platform)

        if incomplete_specs.any?
          resolver.raise_incomplete! incomplete_specs
        end
      end

      if @most_specific_non_local_locked_platform
        if result.incomplete_for_platform?(current_dependencies, @most_specific_non_local_locked_platform)
          @platforms.delete(@most_specific_non_local_locked_platform)
        elsif local_platform_needed_for_resolvability
          @platforms.delete(Bundler.local_platform)
        end
      end

      if should_add_extra_platforms?
        result.add_extra_platforms!(platforms)
      elsif @originally_invalid_platforms.any?
        result.add_originally_invalid_platforms!(platforms, @originally_invalid_platforms)
      end

      SpecSet.new(result.for(dependencies, @platforms | [Gem::Platform::RUBY]))
    end

    def precompute_source_requirements_for_indirect_dependencies?
      sources.non_global_rubygems_sources.all?(&:dependency_api_available?) && !sources.aggregate_global_source?
    end

    def current_platform_locked?
      @platforms.any? do |bundle_platform|
        Bundler.generic_local_platform == bundle_platform || Bundler.local_platform === bundle_platform
      end
    end

    def add_current_platform
      return if @platforms.include?(Bundler.local_platform)

      @most_specific_non_local_locked_platform = find_most_specific_locked_platform
      return if @most_specific_non_local_locked_platform

      @platforms << Bundler.local_platform
      true
    end

    def find_most_specific_locked_platform
      return unless current_platform_locked?

      @most_specific_locked_platform
    end

    def resolve_needed_reason
      if lockfile_exists?
        if unlocking?
          "Re-resolving dependencies because #{unlocking_reason}"
        else
          "Found changes from the lockfile, re-resolving dependencies because #{lockfile_changed_reason}"
        end
      else
        "Resolving dependencies because there's no lockfile"
      end
    end

    def change_reason
      if resolve_needed?
        if unlocking?
          unlocking_reason
        else
          lockfile_changed_reason
        end
      else
        "some dependencies were deleted from your gemfile"
      end
    end

    def unlocking_reason
      unlock_targets = if @gems_to_unlock.any?
        ["gems", @gems_to_unlock]
      elsif @sources_to_unlock.any?
        ["sources", @sources_to_unlock]
      end

      unlock_reason = if unlock_targets
        "#{unlock_targets.first}: (#{unlock_targets.last.join(", ")})"
      else
        @unlocking_ruby ? "ruby" : ""
      end

      "bundler is unlocking #{unlock_reason}"
    end

    def lockfile_changed_reason
      [
        [@source_changes, "the list of sources changed"],
        [@dependency_changes, "the dependencies in your gemfile changed"],
        [@current_platform_missing, "your lockfile is missing the current platform"],
        [@new_platforms.any?, "you are adding a new platform to your lockfile"],
        [@path_changes, "the gemspecs for path gems changed"],
        [@local_changes, "the gemspecs for git local gems changed"],
        [@missing_lockfile_dep, "your lockfile is missing \"#{@missing_lockfile_dep}\""],
        [@unlocking_bundler, "an update to the version of Bundler itself was requested"],
        [@locked_spec_with_missing_checksums, "your lockfile is missing a CHECKSUMS entry for \"#{@locked_spec_with_missing_checksums}\""],
        [@locked_spec_with_missing_deps, "your lockfile includes \"#{@locked_spec_with_missing_deps}\" but not some of its dependencies"],
        [@locked_spec_with_invalid_deps, "your lockfile does not satisfy dependencies of \"#{@locked_spec_with_invalid_deps}\""],
      ].select(&:first).map(&:last).join(", ")
    end

    def pretty_dep(dep)
      SharedHelpers.pretty_dependency(dep)
    end

    # Check if the specs of the given source changed
    # according to the locked source.
    def specs_changed?(source)
      locked = @locked_sources.find {|s| s == source }

      !locked || dependencies_for_source_changed?(source, locked) || specs_for_source_changed?(source)
    end

    def dependencies_for_source_changed?(source, locked_source)
      deps_for_source = @dependencies.select {|dep| dep.source == source }
      locked_deps_for_source = locked_dependencies.select {|dep| dep.source == locked_source }

      deps_for_source.uniq.sort != locked_deps_for_source.sort
    end

    def specs_for_source_changed?(source)
      locked_index = Index.new
      locked_index.use(@locked_specs.select {|s| s.replace_source_with!(source) })

      !locked_index.subset?(source.specs)
    rescue PathError, GitError => e
      Bundler.ui.debug "Assuming that #{source} has not changed since fetching its specs errored (#{e})"
      false
    end

    # Get all locals and override their matching sources.
    # Return true if any of the locals changed (for example,
    # they point to a new revision) or depend on new specs.
    def converge_locals
      locals = []

      Bundler.settings.local_overrides.map do |k, v|
        spec   = @dependencies.find {|s| s.name == k }
        source = spec&.source
        if source&.respond_to?(:local_override!)
          source.unlock! if @gems_to_unlock.include?(spec.name)
          locals << [source, source.local_override!(v)]
        end
      end

      sources_with_changes = locals.select do |source, changed|
        changed || specs_changed?(source)
      end.map(&:first)
      !sources_with_changes.each {|source| @sources_to_unlock << source.name }.empty?
    end

    def check_lockfile
      @locked_spec_with_invalid_deps = nil
      @locked_spec_with_missing_deps = nil
      @locked_spec_with_missing_checksums = nil

      missing_deps = []
      missing_checksums = []
      invalid = []

      @locked_specs.each do |s|
        missing_checksums << s if @locked_checksums && s.source.checksum_store.missing?(s)

        validation = @locked_specs.validate_deps(s)

        missing_deps << s if validation == :missing
        invalid << s if validation == :invalid
      end

      @locked_spec_with_missing_checksums = missing_checksums.first.name if missing_checksums.any?

      if missing_deps.any?
        @locked_specs.delete(missing_deps)

        @locked_spec_with_missing_deps = missing_deps.first.name
      end

      if invalid.any?
        @locked_specs.delete(invalid)

        @locked_spec_with_invalid_deps = invalid.first.name
      end
    end

    def converge_paths
      sources.path_sources.any? do |source|
        specs_changed?(source)
      end
    end

    def converge_sources
      # Replace the sources from the Gemfile with the sources from the Gemfile.lock,
      # if they exist in the Gemfile.lock and are `==`. If you can't find an equivalent
      # source in the Gemfile.lock, use the one from the Gemfile.
      changes = sources.replace_sources!(@locked_sources)

      sources.all_sources.each do |source|
        # has to be done separately, because we want to keep the locked checksum
        # store for a source, even when doing a full update
        if @locked_checksums && @locked_gems && locked_source = @locked_gems.sources.find {|s| s == source && !s.equal?(source) }
          source.checksum_store.merge!(locked_source.checksum_store)
        end
        # If the source is unlockable and the current command allows an unlock of
        # the source (for example, you are doing a `bundle update <foo>` of a git-pinned
        # gem), unlock it. For git sources, this means to unlock the revision, which
        # will cause the `ref` used to be the most recent for the branch (or master) if
        # an explicit `ref` is not used.
        if source.respond_to?(:unlock!) && @sources_to_unlock.include?(source.name)
          source.unlock!
          changes = true
        end
      end

      changes
    end

    def converge_dependencies
      @missing_lockfile_dep = nil
      @changed_dependencies = []

      current_dependencies.each do |dep|
        if dep.source
          dep.source = sources.get(dep.source)
        end

        name = dep.name

        dep_changed = @locked_deps[name].nil?

        unless name == "bundler"
          locked_specs = @originally_locked_specs[name]

          if locked_specs.empty?
            @missing_lockfile_dep = name if dep_changed == false
          else
            if locked_specs.map(&:source).uniq.size > 1
              @locked_specs.delete(locked_specs.select {|s| s.source != dep.source })
            end

            unless dep.matches_spec?(locked_specs.first)
              @gems_to_unlock << name
              dep_changed = true
            end
          end
        end

        @changed_dependencies << name if dep_changed
      end

      @changed_dependencies.any?
    end

    # Remove elements from the locked specs that are expired. This will most
    # commonly happen if the Gemfile has changed since the lockfile was last
    # generated
    def converge_locked_specs
      converged = converge_specs(@locked_specs)

      resolve = SpecSet.new(converged)

      diff = nil

      # Now, we unlock any sources that do not have anymore gems pinned to it
      sources.all_sources.each do |source|
        next unless source.respond_to?(:unlock!)

        unless resolve.any? {|s| s.source == source }
          diff ||= @locked_specs.to_a - resolve.to_a
          source.unlock! if diff.any? {|s| s.source == source }
        end
      end

      resolve
    end

    def converge_specs(specs)
      converged = []
      deps = []

      specs.each do |s|
        name = s.name
        dep = @dependencies.find {|d| s.satisfies?(d) }
        lockfile_source = s.source

        if dep
          replacement_source = dep.source

          deps << dep if !replacement_source || lockfile_source.include?(replacement_source) || new_deps.include?(dep)
        else
          replacement_source = sources.get(lockfile_source)
        end

        # Replace the locked dependency's source with the equivalent source from the Gemfile
        s.source = replacement_source || default_source

        source = s.source
        next if @sources_to_unlock.include?(source.name)

        # Path sources have special logic
        if source.instance_of?(Source::Path) || source.instance_of?(Source::Gemspec) || (source.instance_of?(Source::Git) && !@gems_to_unlock.include?(name) && deps.include?(dep))
          new_spec = source.specs[s].first
          if new_spec
            s.runtime_dependencies.replace(new_spec.runtime_dependencies)
          else
            # If the spec is no longer in the path source, unlock it. This
            # commonly happens if the version changed in the gemspec
            @gems_to_unlock << name
          end
        end

        converged << s
      end

      filter_specs(converged, deps, skips: @gems_to_unlock)
    end

    def metadata_dependencies
      @metadata_dependencies ||= [
        Dependency.new("Ruby\0", Bundler::RubyVersion.system.gem_version),
        Dependency.new("RubyGems\0", Gem::VERSION),
      ]
    end

    def source_requirements
      @source_requirements ||= find_source_requirements
    end

    def find_source_requirements
      # Record the specs available in each gem's source, so that those
      # specs will be available later when the resolver knows where to
      # look for that gemspec (or its dependencies)
      source_requirements = if precompute_source_requirements_for_indirect_dependencies?
        all_requirements = source_map.all_requirements
        { default: default_source }.merge(all_requirements)
      else
        { default: Source::RubygemsAggregate.new(sources, source_map) }.merge(source_map.direct_requirements)
      end
      source_requirements.merge!(source_map.locked_requirements) if nothing_changed?
      metadata_dependencies.each do |dep|
        source_requirements[dep.name] = sources.metadata_source
      end

      default_bundler_source = source_requirements["bundler"] || default_source

      if @unlocking_bundler
        default_bundler_source.add_dependency_names("bundler")
      else
        source_requirements[:default_bundler] = default_bundler_source
        source_requirements["bundler"] = sources.metadata_source # needs to come last to override
      end

      source_requirements
    end

    def default_source
      sources.default_source
    end

    def requested_groups
      values = groups - Bundler.settings[:without] - @optional_groups + Bundler.settings[:with]
      values &= Bundler.settings[:only] unless Bundler.settings[:only].empty?
      values
    end

    def lockfiles_equal?(current, proposed, preserve_unknown_sections)
      if preserve_unknown_sections
        sections_to_ignore = LockfileParser.sections_to_ignore(@locked_bundler_version)
        sections_to_ignore += LockfileParser.unknown_sections_in_lockfile(current)
        sections_to_ignore << LockfileParser::RUBY
        sections_to_ignore << LockfileParser::BUNDLED unless @unlocking_bundler
        pattern = /#{Regexp.union(sections_to_ignore)}\n(\s{2,}.*\n)+/
        whitespace_cleanup = /\n{2,}/
        current = current.gsub(pattern, "\n").gsub(whitespace_cleanup, "\n\n").strip
        proposed = proposed.gsub(pattern, "\n").gsub(whitespace_cleanup, "\n\n").strip
      end
      current == proposed
    end

    def additional_base_requirements_to_prevent_downgrades(resolution_base)
      return resolution_base unless @locked_gems && !sources.expired_sources?(@locked_gems.sources)
      @originally_locked_specs.each do |locked_spec|
        next if locked_spec.source.is_a?(Source::Path)

        name = locked_spec.name
        next if @changed_dependencies.include?(name)

        resolution_base.base_requirements[name] = Gem::Requirement.new(">= #{locked_spec.version}")
      end
      resolution_base
    end

    def additional_base_requirements_to_force_updates(resolution_base)
      return resolution_base if @explicit_unlocks.empty?
      full_update = dup_for_full_unlock.resolve
      @explicit_unlocks.each do |name|
        version = full_update.version_for(name)
        resolution_base.base_requirements[name] = Gem::Requirement.new("= #{version}") if version
      end
      resolution_base
    end

    def dup_for_full_unlock
      unlocked_definition = self.class.new(@lockfile, @dependencies, @sources, true, @ruby_version, @optional_groups, @gemfiles)
      unlocked_definition.source_requirements = source_requirements
      unlocked_definition.gem_version_promoter.tap do |gvp|
        gvp.level = gem_version_promoter.level
        gvp.strict = gem_version_promoter.strict
        gvp.pre = gem_version_promoter.pre
      end
      unlocked_definition
    end

    def remove_invalid_platforms!
      return if Bundler.frozen_bundle?

      skips = (@new_platforms + [Bundler.local_platform]).uniq

      # We should probably avoid removing non-ruby platforms, since that means
      # lockfile will no longer install on those platforms, so a error to give
      # heads up to the user may be better. However, we have tests expecting
      # non ruby platform autoremoval to work, so leaving that in place for
      # now.
      skips |= platforms - [Gem::Platform::RUBY] if @dependency_changes

      @originally_invalid_platforms = @originally_locked_specs.remove_invalid_platforms!(current_dependencies, platforms, skips: skips)
    end

    def source_map
      @source_map ||= SourceMap.new(sources, dependencies, @locked_specs)
    end
  end
end
