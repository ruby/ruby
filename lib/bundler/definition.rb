# frozen_string_literal: true

require_relative "lockfile_parser"
require "set"

module Bundler
  class Definition
    include GemHelpers

    attr_reader(
      :dependencies,
      :locked_deps,
      :locked_gems,
      :platforms,
      :requires,
      :ruby_version,
      :lockfile,
      :gemfiles
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
      if [true, false].include?(unlock)
        @unlocking_bundler = false
        @unlocking = unlock
      else
        unlock = unlock.dup
        @unlocking_bundler = unlock.delete(:bundler)
        unlock.delete_if {|_k, v| Array(v).empty? }
        @unlocking = !unlock.empty?
      end

      @dependencies    = dependencies
      @sources         = sources
      @unlock          = unlock
      @optional_groups = optional_groups
      @remote          = false
      @specs           = nil
      @ruby_version    = ruby_version
      @gemfiles        = gemfiles

      @lockfile               = lockfile
      @lockfile_contents      = String.new
      @locked_bundler_version = nil
      @locked_ruby_version    = nil
      @locked_specs_incomplete_for_platform = false
      @new_platform = nil

      if lockfile && File.exist?(lockfile)
        @lockfile_contents = Bundler.read_file(lockfile)
        @locked_gems = LockfileParser.new(@lockfile_contents)
        @locked_platforms = @locked_gems.platforms
        if Bundler.settings[:force_ruby_platform]
          @platforms = [Gem::Platform::RUBY]
        else
          @platforms = @locked_platforms.dup
        end
        @locked_bundler_version = @locked_gems.bundler_version
        @locked_ruby_version = @locked_gems.ruby_version

        if unlock != true
          @locked_deps    = @locked_gems.dependencies
          @locked_specs   = SpecSet.new(@locked_gems.specs)
          @locked_sources = @locked_gems.sources
        else
          @unlock         = {}
          @locked_deps    = {}
          @locked_specs   = SpecSet.new([])
          @locked_sources = []
        end
      else
        @unlock         = {}
        @platforms      = []
        @locked_gems    = nil
        @locked_deps    = {}
        @locked_specs   = SpecSet.new([])
        @locked_sources = []
        @locked_platforms = []
      end

      @unlock[:gems] ||= []
      @unlock[:sources] ||= []
      @unlock[:ruby] ||= if @ruby_version && locked_ruby_version_object
        @ruby_version.diff(locked_ruby_version_object)
      end
      @unlocking ||= @unlock[:ruby] ||= (!@locked_ruby_version ^ !@ruby_version)

      add_current_platform unless Bundler.frozen_bundle?

      converge_path_sources_to_gemspec_sources
      @path_changes = converge_paths
      @source_changes = converge_sources

      unless @unlock[:lock_shared_dependencies]
        eager_unlock = expand_dependencies(@unlock[:gems], true)
        @unlock[:gems] = @locked_specs.for(eager_unlock, [], false, false, false).map(&:name)
      end

      @dependency_changes = converge_dependencies
      @local_changes = converge_locals

      @requires = compute_requires
    end

    def gem_version_promoter
      @gem_version_promoter ||= begin
        locked_specs =
          if unlocking? && @locked_specs.empty? && !@lockfile_contents.empty?
            # Definition uses an empty set of locked_specs to indicate all gems
            # are unlocked, but GemVersionPromoter needs the locked_specs
            # for conservative comparison.
            Bundler::SpecSet.new(@locked_gems.specs)
          else
            @locked_specs
          end
        GemVersionPromoter.new(locked_specs, @unlock[:gems])
      end
    end

    def resolve_with_cache!
      raise "Specs already loaded" if @specs
      sources.cached!
      specs
    end

    def resolve_remotely!
      raise "Specs already loaded" if @specs
      @remote = true
      sources.remote!
      specs
    end

    # For given dependency list returns a SpecSet with Gemspec of all the required
    # dependencies.
    #  1. The method first resolves the dependencies specified in Gemfile
    #  2. After that it tries and fetches gemspec of resolved dependencies
    #
    # @return [Bundler::SpecSet]
    def specs
      @specs ||= begin
        begin
          specs = resolve.materialize(requested_dependencies)
        rescue GemNotFound => e # Handle yanked gem
          gem_name, gem_version = extract_gem_info(e)
          locked_gem = @locked_specs[gem_name].last
          raise if locked_gem.nil? || locked_gem.version.to_s != gem_version || !@remote
          raise GemNotFound, "Your bundle is locked to #{locked_gem}, but that version could not " \
                             "be found in any of the sources listed in your Gemfile. If you haven't changed sources, " \
                             "that means the author of #{locked_gem} has removed it. You'll need to update your bundle " \
                             "to a version other than #{locked_gem} that hasn't been removed in order to install."
        end
        unless specs["bundler"].any?
          bundler = sources.metadata_source.specs.search(Gem::Dependency.new("bundler", VERSION)).last
          specs["bundler"] = bundler
        end

        specs
      end
    end

    def new_specs
      specs - @locked_specs
    end

    def removed_specs
      @locked_specs - specs
    end

    def missing_specs
      missing = []
      resolve.materialize(requested_dependencies, missing)
      missing
    end

    def missing_specs?
      missing = missing_specs
      return false if missing.empty?
      Bundler.ui.debug "The definition is missing #{missing.map(&:full_name)}"
      true
    rescue BundlerError => e
      @index = nil
      @resolve = nil
      @specs = nil
      @gem_version_promoter = nil

      Bundler.ui.debug "The definition is missing dependencies, failed to resolve & materialize locally (#{e})"
      true
    end

    def requested_specs
      @requested_specs ||= begin
        groups = requested_groups
        groups.map!(&:to_sym)
        specs_for(groups)
      end
    end

    def requested_dependencies
      groups = requested_groups
      groups.map!(&:to_sym)
      dependencies_for(groups)
    end

    def current_dependencies
      dependencies.select do |d|
        d.should_include? && !d.gem_platforms(@platforms).empty?
      end
    end

    def specs_for(groups)
      deps = dependencies_for(groups)
      specs.for(expand_dependencies(deps))
    end

    def dependencies_for(groups)
      current_dependencies.reject do |d|
        (d.groups & groups).empty?
      end
    end

    # Resolve all the dependencies specified in Gemfile. It ensures that
    # dependencies that have been already resolved via locked file and are fresh
    # are reused when resolving dependencies
    #
    # @return [SpecSet] resolved dependencies
    def resolve
      @resolve ||= begin
        last_resolve = converge_locked_specs
        resolve =
          if Bundler.frozen_bundle?
            Bundler.ui.debug "Frozen, using resolution from the lockfile"
            last_resolve
          elsif !unlocking? && nothing_changed?
            Bundler.ui.debug("Found no changes, using resolution from the lockfile")
            last_resolve
          else
            # Run a resolve against the locally available gems
            Bundler.ui.debug("Found changes from the lockfile, re-resolving dependencies because #{change_reason}")
            last_resolve.merge Resolver.resolve(expanded_dependencies, index, source_requirements, last_resolve, gem_version_promoter, additional_base_requirements_for_resolve, platforms)
          end

        # filter out gems that _can_ be installed on multiple platforms, but don't need
        # to be
        resolve.for(expand_dependencies(dependencies, true), [], false, false, false)
      end
    end

    def index
      @index ||= Index.build do |idx|
        dependency_names = @dependencies.map(&:name)

        sources.all_sources.each do |source|
          source.dependency_names = dependency_names - pinned_spec_names(source)
          idx.add_source source.specs
          dependency_names.concat(source.unmet_deps).uniq!
        end

        double_check_for_index(idx, dependency_names)
      end
    end

    # Suppose the gem Foo depends on the gem Bar.  Foo exists in Source A.  Bar has some versions that exist in both
    # sources A and B.  At this point, the API request will have found all the versions of Bar in source A,
    # but will not have found any versions of Bar from source B, which is a problem if the requested version
    # of Foo specifically depends on a version of Bar that is only found in source B. This ensures that for
    # each spec we found, we add all possible versions from all sources to the index.
    def double_check_for_index(idx, dependency_names)
      pinned_names = pinned_spec_names
      loop do
        idxcount = idx.size

        names = :names # do this so we only have to traverse to get dependency_names from the index once
        unmet_dependency_names = lambda do
          return names unless names == :names
          new_names = sources.all_sources.map(&:dependency_names_to_double_check)
          return names = nil if new_names.compact!
          names = new_names.flatten(1).concat(dependency_names)
          names.uniq!
          names -= pinned_names
          names
        end

        sources.all_sources.each do |source|
          source.double_check_for(unmet_dependency_names)
        end

        break if idxcount == idx.size
      end
    end
    private :double_check_for_index

    def has_rubygems_remotes?
      sources.rubygems_sources.any? {|s| s.remotes.any? }
    end

    def spec_git_paths
      sources.git_sources.map {|s| File.realpath(s.path) if File.exist?(s.path) }.compact
    end

    def groups
      dependencies.map(&:groups).flatten.uniq
    end

    def lock(file, preserve_unknown_sections = false)
      contents = to_lock

      # Convert to \r\n if the existing lock has them
      # i.e., Windows with `git config core.autocrlf=true`
      contents.gsub!(/\n/, "\r\n") if @lockfile_contents.match("\r\n")

      if @locked_bundler_version
        locked_major = @locked_bundler_version.segments.first
        current_major = Gem::Version.create(Bundler::VERSION).segments.first

        if updating_major = locked_major < current_major
          Bundler.ui.warn "Warning: the lockfile is being updated to Bundler #{current_major}, " \
                          "after which you will be unable to return to Bundler #{@locked_bundler_version.segments.first}."
        end
      end

      preserve_unknown_sections ||= !updating_major && (Bundler.frozen_bundle? || !(unlocking? || @unlocking_bundler))

      return if file && File.exist?(file) && lockfiles_equal?(@lockfile_contents, contents, preserve_unknown_sections)

      if Bundler.frozen_bundle?
        Bundler.ui.error "Cannot write a changed lockfile while frozen."
        return
      end

      SharedHelpers.filesystem_access(file) do |p|
        File.open(p, "wb") {|f| f.puts(contents) }
      end
    end

    def locked_bundler_version
      if @locked_bundler_version && @locked_bundler_version < Gem::Version.new(Bundler::VERSION)
        new_version = Bundler::VERSION
      end

      new_version || @locked_bundler_version || Bundler::VERSION
    end

    def locked_ruby_version
      return unless ruby_version
      if @unlock[:ruby] || !@locked_ruby_version
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

    def to_lock
      require_relative "lockfile_generator"
      LockfileGenerator.generate(self)
    end

    def ensure_equivalent_gemfile_and_lockfile(explicit_flag = false)
      msg = String.new
      msg << "You are trying to install in deployment mode after changing\n" \
             "your Gemfile. Run `bundle install` elsewhere and add the\n" \
             "updated #{Bundler.default_lockfile.relative_path_from(SharedHelpers.pwd)} to version control."

      unless explicit_flag
        suggested_command = if Bundler.settings.locations("frozen").keys.&([:global, :local]).any?
          "bundle config unset frozen"
        elsif Bundler.settings.locations("deployment").keys.&([:global, :local]).any?
          "bundle config unset deployment"
        end
        msg << "\n\nIf this is a development machine, remove the #{Bundler.default_gemfile} " \
               "freeze \nby running `#{suggested_command}`."
      end

      added =   []
      deleted = []
      changed = []

      new_platforms = @platforms - @locked_platforms
      deleted_platforms = @locked_platforms - @platforms
      added.concat new_platforms.map {|p| "* platform: #{p}" }
      deleted.concat deleted_platforms.map {|p| "* platform: #{p}" }

      gemfile_sources = sources.lock_sources

      new_sources = gemfile_sources - @locked_sources
      deleted_sources = @locked_sources - gemfile_sources

      new_deps = @dependencies - @locked_deps.values
      deleted_deps = @locked_deps.values - @dependencies

      # Check if it is possible that the source is only changed thing
      if (new_deps.empty? && deleted_deps.empty?) && (!new_sources.empty? && !deleted_sources.empty?)
        new_sources.reject! {|source| (source.path? && source.path.exist?) || equivalent_rubygems_remotes?(source) }
        deleted_sources.reject! {|source| (source.path? && source.path.exist?) || equivalent_rubygems_remotes?(source) }
      end

      if @locked_sources != gemfile_sources
        if new_sources.any?
          added.concat new_sources.map {|source| "* source: #{source}" }
        end

        if deleted_sources.any?
          deleted.concat deleted_sources.map {|source| "* source: #{source}" }
        end
      end

      added.concat new_deps.map {|d| "* #{pretty_dep(d)}" } if new_deps.any?
      if deleted_deps.any?
        deleted.concat deleted_deps.map {|d| "* #{pretty_dep(d)}" }
      end

      both_sources = Hash.new {|h, k| h[k] = [] }
      @dependencies.each {|d| both_sources[d.name][0] = d }
      @locked_deps.each  {|name, d| both_sources[name][1] = d.source }

      both_sources.each do |name, (dep, lock_source)|
        next if lock_source.nil? || (dep && lock_source.can_lock?(dep))
        gemfile_source_name = (dep && dep.source) || "no specified source"
        lockfile_source_name = lock_source
        changed << "* #{name} from `#{gemfile_source_name}` to `#{lockfile_source_name}`"
      end

      reason = change_reason
      msg << "\n\n#{reason.split(", ").map(&:capitalize).join("\n")}" unless reason.strip.empty?
      msg << "\n\nYou have added to the Gemfile:\n" << added.join("\n") if added.any?
      msg << "\n\nYou have deleted from the Gemfile:\n" << deleted.join("\n") if deleted.any?
      msg << "\n\nYou have changed in the Gemfile:\n" << changed.join("\n") if changed.any?
      msg << "\n"

      raise ProductionError, msg if added.any? || deleted.any? || changed.any? || !nothing_changed?
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
      return if @platforms.any? do |bundle_platform|
        Bundler.rubygems.platforms.any? do |local_platform|
          MatchPlatform.platforms_match?(bundle_platform, local_platform)
        end
      end

      raise ProductionError, "Your bundle only supports platforms #{@platforms.map(&:to_s)} " \
        "but your local platforms are #{Bundler.rubygems.platforms.map(&:to_s)}, and " \
        "there's no compatible match between those two lists."
    end

    def add_platform(platform)
      @new_platform ||= !@platforms.include?(platform)
      @platforms |= [platform]
    end

    def remove_platform(platform)
      return if @platforms.delete(Gem::Platform.new(platform))
      raise InvalidOption, "Unable to remove the platform `#{platform}` since the only platforms are #{@platforms.join ", "}"
    end

    def find_resolved_spec(current_spec)
      specs.find_by_name_and_platform(current_spec.name, current_spec.platform)
    end

    def find_indexed_specs(current_spec)
      index[current_spec.name].select {|spec| spec.match_platform(current_spec.platform) }.sort_by(&:version)
    end

    attr_reader :sources
    private :sources

    def nothing_changed?
      !@source_changes && !@dependency_changes && !@new_platform && !@path_changes && !@local_changes && !@locked_specs_incomplete_for_platform
    end

    def unlocking?
      @unlocking
    end

    private

    def add_current_platform
      current_platforms.each {|platform| add_platform(platform) }
    end

    def current_platforms
      [local_platform, generic_local_platform].uniq
    end

    def change_reason
      if unlocking?
        unlock_reason = @unlock.reject {|_k, v| Array(v).empty? }.map do |k, v|
          if v == true
            k.to_s
          else
            v = Array(v)
            "#{k}: (#{v.join(", ")})"
          end
        end.join(", ")
        return "bundler is unlocking #{unlock_reason}"
      end
      [
        [@source_changes, "the list of sources changed"],
        [@dependency_changes, "the dependencies in your gemfile changed"],
        [@new_platform, "you added a new platform to your gemfile"],
        [@path_changes, "the gemspecs for path gems changed"],
        [@local_changes, "the gemspecs for git local gems changed"],
        [@locked_specs_incomplete_for_platform, "the lockfile does not have all gems needed for the current platform"],
      ].select(&:first).map(&:last).join(", ")
    end

    def pretty_dep(dep, source = false)
      SharedHelpers.pretty_dependency(dep, source)
    end

    # Check if the specs of the given source changed
    # according to the locked source.
    def specs_changed?(source)
      locked = @locked_sources.find {|s| s == source }

      !locked || dependencies_for_source_changed?(source, locked) || specs_for_source_changed?(source)
    end

    def dependencies_for_source_changed?(source, locked_source = source)
      deps_for_source = @dependencies.select {|s| s.source == source }
      locked_deps_for_source = @locked_deps.values.select {|dep| dep.source == locked_source }

      Set.new(deps_for_source) != Set.new(locked_deps_for_source)
    end

    def specs_for_source_changed?(source)
      locked_index = Index.new
      locked_index.use(@locked_specs.select {|s| source.can_lock?(s) })

      # order here matters, since Index#== is checking source.specs.include?(locked_index)
      locked_index != source.specs
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
        source = spec && spec.source
        if source && source.respond_to?(:local_override!)
          source.unlock! if @unlock[:gems].include?(spec.name)
          locals << [source, source.local_override!(v)]
        end
      end

      sources_with_changes = locals.select do |source, changed|
        changed || specs_changed?(source)
      end.map(&:first)
      !sources_with_changes.each {|source| @unlock[:sources] << source.name }.empty?
    end

    def converge_paths
      sources.path_sources.any? do |source|
        specs_changed?(source)
      end
    end

    def converge_path_source_to_gemspec_source(source)
      return source unless source.instance_of?(Source::Path)
      gemspec_source = sources.path_sources.find {|s| s.is_a?(Source::Gemspec) && s.as_path_source == source }
      gemspec_source || source
    end

    def converge_path_sources_to_gemspec_sources
      @locked_sources.map! do |source|
        converge_path_source_to_gemspec_source(source)
      end
      @locked_specs.each do |spec|
        spec.source &&= converge_path_source_to_gemspec_source(spec.source)
      end
      @locked_deps.each do |_, dep|
        dep.source &&= converge_path_source_to_gemspec_source(dep.source)
      end
    end

    def converge_rubygems_sources
      return false if Bundler.feature_flag.disable_multisource?

      changes = false

      # Get the RubyGems sources from the Gemfile.lock
      locked_gem_sources = @locked_sources.select {|s| s.is_a?(Source::Rubygems) }
      # Get the RubyGems remotes from the Gemfile
      actual_remotes = sources.rubygems_remotes

      # If there is a RubyGems source in both
      if !locked_gem_sources.empty? && !actual_remotes.empty?
        locked_gem_sources.each do |locked_gem|
          # Merge the remotes from the Gemfile into the Gemfile.lock
          changes |= locked_gem.replace_remotes(actual_remotes, Bundler.settings[:allow_deployment_source_credential_changes])
        end
      end

      changes
    end

    def converge_sources
      changes = false

      changes |= converge_rubygems_sources

      # Replace the sources from the Gemfile with the sources from the Gemfile.lock,
      # if they exist in the Gemfile.lock and are `==`. If you can't find an equivalent
      # source in the Gemfile.lock, use the one from the Gemfile.
      changes |= sources.replace_sources!(@locked_sources)

      sources.all_sources.each do |source|
        # If the source is unlockable and the current command allows an unlock of
        # the source (for example, you are doing a `bundle update <foo>` of a git-pinned
        # gem), unlock it. For git sources, this means to unlock the revision, which
        # will cause the `ref` used to be the most recent for the branch (or master) if
        # an explicit `ref` is not used.
        if source.respond_to?(:unlock!) && @unlock[:sources].include?(source.name)
          source.unlock!
          changes = true
        end
      end

      changes
    end

    def converge_dependencies
      frozen = Bundler.frozen_bundle?
      (@dependencies + @locked_deps.values).each do |dep|
        locked_source = @locked_deps[dep.name]
        # This is to make sure that if bundler is installing in deployment mode and
        # after locked_source and sources don't match, we still use locked_source.
        if frozen && !locked_source.nil? &&
            locked_source.respond_to?(:source) && locked_source.source.instance_of?(Source::Path) && locked_source.source.path.exist?
          dep.source = locked_source.source
        elsif dep.source
          dep.source = sources.get(dep.source)
        end
      end

      changes = false
      # We want to know if all match, but don't want to check all entries
      # This means we need to return false if any dependency doesn't match
      # the lock or doesn't exist in the lock.
      @dependencies.each do |dependency|
        unless locked_dep = @locked_deps[dependency.name]
          changes = true
          next
        end

        # Gem::Dependency#== matches Gem::Dependency#type. As the lockfile
        # doesn't carry a notion of the dependency type, if you use
        # add_development_dependency in a gemspec that's loaded with the gemspec
        # directive, the lockfile dependencies and resolved dependencies end up
        # with a mismatch on #type. Work around that by setting the type on the
        # dep from the lockfile.
        locked_dep.instance_variable_set(:@type, dependency.type)

        # We already know the name matches from the hash lookup
        # so we only need to check the requirement now
        changes ||= dependency.requirement != locked_dep.requirement
      end

      changes
    end

    # Remove elements from the locked specs that are expired. This will most
    # commonly happen if the Gemfile has changed since the lockfile was last
    # generated
    def converge_locked_specs
      deps = []

      # Build a list of dependencies that are the same in the Gemfile
      # and Gemfile.lock. If the Gemfile modified a dependency, but
      # the gem in the Gemfile.lock still satisfies it, this is fine
      # too.
      @dependencies.each do |dep|
        locked_dep = @locked_deps[dep.name]

        # If the locked_dep doesn't match the dependency we're looking for then we ignore the locked_dep
        locked_dep = nil unless locked_dep == dep

        if in_locked_deps?(dep, locked_dep) || satisfies_locked_spec?(dep)
          deps << dep
        elsif dep.source.is_a?(Source::Path) && dep.current_platform? && (!locked_dep || dep.source != locked_dep.source)
          @locked_specs.each do |s|
            @unlock[:gems] << s.name if s.source == dep.source
          end

          dep.source.unlock! if dep.source.respond_to?(:unlock!)
          dep.source.specs.each {|s| @unlock[:gems] << s.name }
        end
      end

      unlock_source_unlocks_spec = Bundler.feature_flag.unlock_source_unlocks_spec?

      converged = []
      @locked_specs.each do |s|
        # Replace the locked dependency's source with the equivalent source from the Gemfile
        dep = @dependencies.find {|d| s.satisfies?(d) }
        s.source = (dep && dep.source) || sources.get(s.source)

        # Don't add a spec to the list if its source is expired. For example,
        # if you change a Git gem to RubyGems.
        next if s.source.nil?
        next if @unlock[:sources].include?(s.source.name)

        # XXX This is a backwards-compatibility fix to preserve the ability to
        # unlock a single gem by passing its name via `--source`. See issue #3759
        # TODO: delete in Bundler 2
        next if unlock_source_unlocks_spec && @unlock[:sources].include?(s.name)

        # If the spec is from a path source and it doesn't exist anymore
        # then we unlock it.

        # Path sources have special logic
        if s.source.instance_of?(Source::Path) || s.source.instance_of?(Source::Gemspec)
          new_specs = begin
            s.source.specs
          rescue PathError, GitError
            # if we won't need the source (according to the lockfile),
            # don't error if the path/git source isn't available
            next if @locked_specs.
                    for(requested_dependencies, [], false, true, false).
                    none? {|locked_spec| locked_spec.source == s.source }

            raise
          end

          new_spec = new_specs[s].first

          # If the spec is no longer in the path source, unlock it. This
          # commonly happens if the version changed in the gemspec
          next unless new_spec

          new_runtime_deps = new_spec.dependencies.select {|d| d.type != :development }
          old_runtime_deps = s.dependencies.select {|d| d.type != :development }
          # If the dependencies of the path source have changed and locked spec can't satisfy new dependencies, unlock it
          next unless new_runtime_deps.sort == old_runtime_deps.sort || new_runtime_deps.all? {|d| satisfies_locked_spec?(d) }

          s.dependencies.replace(new_spec.dependencies)
        end

        converged << s
      end

      resolve = SpecSet.new(converged)
      @locked_specs_incomplete_for_platform = !resolve.for(expand_dependencies(requested_dependencies & deps), @unlock[:gems], true, true)
      resolve = resolve.for(expand_dependencies(deps, true), @unlock[:gems], false, false, false)
      diff    = nil

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

    def in_locked_deps?(dep, locked_dep)
      # Because the lockfile can't link a dep to a specific remote, we need to
      # treat sources as equivalent anytime the locked dep has all the remotes
      # that the Gemfile dep does.
      locked_dep && locked_dep.source && dep.source && locked_dep.source.include?(dep.source)
    end

    def satisfies_locked_spec?(dep)
      @locked_specs[dep].any? {|s| s.satisfies?(dep) && (!dep.source || s.source.include?(dep.source)) }
    end

    # This list of dependencies is only used in #resolve, so it's OK to add
    # the metadata dependencies here
    def expanded_dependencies
      @expanded_dependencies ||= begin
        expand_dependencies(dependencies + metadata_dependencies, @remote)
      end
    end

    def metadata_dependencies
      @metadata_dependencies ||= begin
        ruby_versions = ruby_version_requirements(@ruby_version)
        [
          Dependency.new("Ruby\0", ruby_versions),
          Dependency.new("RubyGems\0", Gem::VERSION),
        ]
      end
    end

    def ruby_version_requirements(ruby_version)
      return [] unless ruby_version
      if ruby_version.patchlevel
        [ruby_version.to_gem_version_with_patchlevel]
      else
        ruby_version.versions.map do |version|
          requirement = Gem::Requirement.new(version)
          if requirement.exact?
            "~> #{version}.0"
          else
            requirement
          end
        end
      end
    end

    def expand_dependencies(dependencies, remote = false)
      deps = []
      dependencies.each do |dep|
        dep = Dependency.new(dep, ">= 0") unless dep.respond_to?(:name)
        next unless remote || dep.current_platform?
        target_platforms = dep.gem_platforms(remote ? Resolver.sort_platforms(@platforms) : [generic_local_platform])
        deps += expand_dependency_with_platforms(dep, target_platforms)
      end
      deps
    end

    def expand_dependency_with_platforms(dep, platforms)
      platforms.map do |p|
        DepProxy.new(dep, p)
      end
    end

    def source_requirements
      # Load all specs from remote sources
      index

      # Record the specs available in each gem's source, so that those
      # specs will be available later when the resolver knows where to
      # look for that gemspec (or its dependencies)
      default = sources.default_source
      source_requirements = { :default => default }
      default = nil unless Bundler.feature_flag.disable_multisource?
      dependencies.each do |dep|
        next unless source = dep.source || default
        source_requirements[dep.name] = source
      end
      metadata_dependencies.each do |dep|
        source_requirements[dep.name] = sources.metadata_source
      end
      source_requirements["bundler"] = sources.metadata_source # needs to come last to override
      source_requirements
    end

    def pinned_spec_names(skip = nil)
      pinned_names = []
      default = Bundler.feature_flag.disable_multisource? && sources.default_source
      @dependencies.each do |dep|
        next unless dep_source = dep.source || default
        next if dep_source == skip
        pinned_names << dep.name
      end
      pinned_names
    end

    def requested_groups
      groups - Bundler.settings[:without] - @optional_groups + Bundler.settings[:with]
    end

    def lockfiles_equal?(current, proposed, preserve_unknown_sections)
      if preserve_unknown_sections
        sections_to_ignore = LockfileParser.sections_to_ignore(@locked_bundler_version)
        sections_to_ignore += LockfileParser.unknown_sections_in_lockfile(current)
        sections_to_ignore += LockfileParser::ENVIRONMENT_VERSION_SECTIONS
        pattern = /#{Regexp.union(sections_to_ignore)}\n(\s{2,}.*\n)+/
        whitespace_cleanup = /\n{2,}/
        current = current.gsub(pattern, "\n").gsub(whitespace_cleanup, "\n\n").strip
        proposed = proposed.gsub(pattern, "\n").gsub(whitespace_cleanup, "\n\n").strip
      end
      current == proposed
    end

    def extract_gem_info(error)
      # This method will extract the error message like "Could not find foo-1.2.3 in any of the sources"
      # to an array. The first element will be the gem name (e.g. foo), the second will be the version number.
      error.message.scan(/Could not find (\w+)-(\d+(?:\.\d+)+)/).flatten
    end

    def compute_requires
      dependencies.reduce({}) do |requires, dep|
        next requires unless dep.should_include?
        requires[dep.name] = Array(dep.autorequire || dep.name).map do |file|
          # Allow `require: true` as an alias for `require: <name>`
          file == true ? dep.name : file
        end
        requires
      end
    end

    def additional_base_requirements_for_resolve
      return [] unless @locked_gems && Bundler.feature_flag.only_update_to_newer_versions?
      dependencies_by_name = dependencies.inject({}) {|memo, dep| memo.update(dep.name => dep) }
      @locked_gems.specs.reduce({}) do |requirements, locked_spec|
        name = locked_spec.name
        dependency = dependencies_by_name[name]
        next requirements unless dependency
        next requirements if @locked_gems.dependencies[name] != dependency
        next requirements if dependency.source.is_a?(Source::Path)
        dep = Gem::Dependency.new(name, ">= #{locked_spec.version}")
        requirements[name] = DepProxy.new(dep, locked_spec.platform)
        requirements
      end.values
    end

    def equivalent_rubygems_remotes?(source)
      return false unless source.is_a?(Source::Rubygems)

      Bundler.settings[:allow_deployment_source_credential_changes] && source.equivalent_remotes?(sources.rubygems_remotes)
    end
  end
end
