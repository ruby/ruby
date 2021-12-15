# frozen_string_literal: true

module Bundler
  class Resolver
    require_relative "vendored_molinillo"
    require_relative "resolver/spec_group"

    include GemHelpers

    # Figures out the best possible configuration of gems that satisfies
    # the list of passed dependencies and any child dependencies without
    # causing any gem activation errors.
    #
    # ==== Parameters
    # *dependencies<Gem::Dependency>:: The list of dependencies to resolve
    #
    # ==== Returns
    # <GemBundle>,nil:: If the list of dependencies can be resolved, a
    #   collection of gemspecs is returned. Otherwise, nil is returned.
    def self.resolve(requirements, source_requirements = {}, base = [], gem_version_promoter = GemVersionPromoter.new, additional_base_requirements = [], platforms = nil)
      base = SpecSet.new(base) unless base.is_a?(SpecSet)
      resolver = new(source_requirements, base, gem_version_promoter, additional_base_requirements, platforms)
      result = resolver.start(requirements)
      SpecSet.new(SpecSet.new(result).for(requirements.reject{|dep| dep.name.end_with?("\0") }))
    end

    def initialize(source_requirements, base, gem_version_promoter, additional_base_requirements, platforms)
      @source_requirements = source_requirements
      @base = base
      @resolver = Molinillo::Resolver.new(self, self)
      @search_for = {}
      @base_dg = Molinillo::DependencyGraph.new
      @base.each do |ls|
        dep = Dependency.new(ls.name, ls.version)
        @base_dg.add_vertex(ls.name, DepProxy.get_proxy(dep, ls.platform), true)
      end
      additional_base_requirements.each {|d| @base_dg.add_vertex(d.name, d) }
      @platforms = platforms.reject {|p| p != Gem::Platform::RUBY && (platforms - [p]).any? {|pl| generic(pl) == p } }
      @resolving_only_for_ruby = platforms == [Gem::Platform::RUBY]
      @gem_version_promoter = gem_version_promoter
      @use_gvp = Bundler.feature_flag.use_gem_version_promoter_for_major_updates? || !@gem_version_promoter.major?
    end

    def start(requirements)
      @gem_version_promoter.prerelease_specified = @prerelease_specified = {}
      requirements.each {|dep| @prerelease_specified[dep.name] ||= dep.prerelease? }

      verify_gemfile_dependencies_are_found!(requirements)
      dg = @resolver.resolve(requirements, @base_dg)
      dg.
        map(&:payload).
        reject {|sg| sg.name.end_with?("\0") }.
        map(&:to_specs).
        flatten
    rescue Molinillo::VersionConflict => e
      message = version_conflict_message(e)
      raise VersionConflict.new(e.conflicts.keys.uniq, message)
    rescue Molinillo::CircularDependencyError => e
      names = e.dependencies.sort_by(&:name).map {|d| "gem '#{d.name}'" }
      raise CyclicDependencyError, "Your bundle requires gems that depend" \
        " on each other, creating an infinite loop. Please remove" \
        " #{names.count > 1 ? "either " : ""}#{names.join(" or ")}" \
        " and try again."
    end

    include Molinillo::UI

    # Conveys debug information to the user.
    #
    # @param [Integer] depth the current depth of the resolution process.
    # @return [void]
    def debug(depth = 0)
      return unless debug?
      debug_info = yield
      debug_info = debug_info.inspect unless debug_info.is_a?(String)
      puts debug_info.split("\n").map {|s| depth == 0 ? "BUNDLER: #{s}" : "BUNDLER(#{depth}): #{s}" }
    end

    def debug?
      return @debug_mode if defined?(@debug_mode)
      @debug_mode =
        ENV["BUNDLER_DEBUG_RESOLVER"] ||
        ENV["BUNDLER_DEBUG_RESOLVER_TREE"] ||
        ENV["DEBUG_RESOLVER"] ||
        ENV["DEBUG_RESOLVER_TREE"] ||
        false
    end

    def before_resolution
      Bundler.ui.info "Resolving dependencies...", debug?
    end

    def after_resolution
      Bundler.ui.info ""
    end

    def indicate_progress
      Bundler.ui.info ".", false unless debug?
    end

    include Molinillo::SpecificationProvider

    def dependencies_for(specification)
      specification.dependencies_for_activated_platforms
    end

    def search_for(dependency_proxy)
      platform = dependency_proxy.__platform
      dependency = dependency_proxy.dep
      name = dependency.name
      @search_for[dependency_proxy] ||= begin
        results = results_for(dependency, @base[name])

        if vertex = @base_dg.vertex_named(name)
          locked_requirement = vertex.payload.requirement
        end

        if !@prerelease_specified[name] && (!@use_gvp || locked_requirement.nil?)
          # Move prereleases to the beginning of the list, so they're considered
          # last during resolution.
          pre, results = results.partition {|spec| spec.version.prerelease? }
          results = pre + results
        end

        spec_groups = if results.any?
          nested = []
          results.each do |spec|
            version, specs = nested.last
            if version == spec.version
              specs << spec
            else
              nested << [spec.version, [spec]]
            end
          end
          nested.reduce([]) do |groups, (version, specs)|
            next groups if locked_requirement && !locked_requirement.satisfied_by?(version)
            next groups unless specs.any? {|spec| spec.match_platform(platform) }

            specs_by_platform = Hash.new do |current_specs, current_platform|
              current_specs[current_platform] = select_best_platform_match(specs, current_platform)
            end

            spec_group_ruby = SpecGroup.create_for(specs_by_platform, [Gem::Platform::RUBY], Gem::Platform::RUBY)
            groups << spec_group_ruby if spec_group_ruby

            next groups if @resolving_only_for_ruby

            spec_group = SpecGroup.create_for(specs_by_platform, @platforms, platform)
            groups << spec_group

            groups
          end
        else
          []
        end
        # GVP handles major itself, but it's still a bit risky to trust it with it
        # until we get it settled with new behavior. For 2.x it can take over all cases.
        if !@use_gvp
          spec_groups
        else
          @gem_version_promoter.sort_versions(dependency, spec_groups)
        end
      end
    end

    def index_for(dependency)
      source_for(dependency.name).specs
    end

    def source_for(name)
      @source_requirements[name] || @source_requirements[:default]
    end

    def results_for(dependency, base)
      index_for(dependency).search(dependency, base)
    end

    def name_for(dependency)
      dependency.name
    end

    def name_for_explicit_dependency_source
      Bundler.default_gemfile.basename.to_s
    rescue StandardError
      "Gemfile"
    end

    def name_for_locking_dependency_source
      Bundler.default_lockfile.basename.to_s
    rescue StandardError
      "Gemfile.lock"
    end

    def requirement_satisfied_by?(requirement, activated, spec)
      requirement.matches_spec?(spec) || spec.source.is_a?(Source::Gemspec)
    end

    def dependencies_equal?(dependencies, other_dependencies)
      dependencies.map(&:dep) == other_dependencies.map(&:dep)
    end

    def sort_dependencies(dependencies, activated, conflicts)
      dependencies.sort_by do |dependency|
        name = name_for(dependency)
        vertex = activated.vertex_named(name)
        [
          @base_dg.vertex_named(name) ? 0 : 1,
          vertex.payload ? 0 : 1,
          vertex.root? ? 0 : 1,
          amount_constrained(dependency),
          conflicts[name] ? 0 : 1,
          vertex.payload ? 0 : search_for(dependency).count,
          self.class.platform_sort_key(dependency.__platform),
        ]
      end
    end

    def self.platform_sort_key(platform)
      # Prefer specific platform to not specific platform
      return ["99-LAST", "", "", ""] if Gem::Platform::RUBY == platform
      ["00", *platform.to_a.map {|part| part || "" }]
    end

    private

    # returns an integer \in (-\infty, 0]
    # a number closer to 0 means the dependency is less constraining
    #
    # dependencies w/ 0 or 1 possibilities (ignoring version requirements)
    # are given very negative values, so they _always_ sort first,
    # before dependencies that are unconstrained
    def amount_constrained(dependency)
      @amount_constrained ||= {}
      @amount_constrained[dependency.name] ||= begin
        if (base = @base[dependency.name]) && !base.empty?
          dependency.requirement.satisfied_by?(base.first.version) ? 0 : 1
        else
          all = index_for(dependency).search(dependency.name).size

          if all <= 1
            all - 1_000_000
          else
            search = search_for(dependency)
            search = @prerelease_specified[dependency.name] ? search.count : search.count {|s| !s.version.prerelease? }
            search - all
          end
        end
      end
    end

    def verify_gemfile_dependencies_are_found!(requirements)
      requirements.each do |requirement|
        name = requirement.name
        next if name == "bundler"
        next unless search_for(requirement).empty?

        if (base = @base[name]) && !base.empty?
          version = base.first.version
          message = "You have requested:\n" \
            "  #{name} #{requirement.requirement}\n\n" \
            "The bundle currently has #{name} locked at #{version}.\n" \
            "Try running `bundle update #{name}`\n\n" \
            "If you are updating multiple gems in your Gemfile at once,\n" \
            "try passing them all to `bundle update`"
        else
          message = gem_not_found_message(name, requirement, source_for(name))
        end
        raise GemNotFound, message
      end
    end

    def gem_not_found_message(name, requirement, source, extra_message = "")
      specs = source.specs.search(name)
      matching_part = name
      requirement_label = SharedHelpers.pretty_dependency(requirement)
      cache_message = begin
                          " or in gems cached in #{Bundler.settings.app_cache_path}" if Bundler.app_cache.exist?
                        rescue GemfileNotFound
                          nil
                        end
      specs_matching_requirement = specs.select {| spec| requirement.matches_spec?(spec) }

      if specs_matching_requirement.any?
        specs = specs_matching_requirement
        matching_part = requirement_label
        requirement_label = "#{requirement_label} #{requirement.__platform}"
      end

      message = String.new("Could not find gem '#{requirement_label}'#{extra_message} in #{source}#{cache_message}.\n")

      if specs.any?
        message << "\nThe source contains the following gems matching '#{matching_part}':\n"
        message << specs.map {|s| "  * #{s.full_name}" }.join("\n")
      end

      message
    end

    def version_conflict_message(e)
      # only show essential conflicts, if possible
      conflicts = e.conflicts.dup

      if conflicts["bundler"]
        conflicts.replace("bundler" => conflicts["bundler"])
      else
        conflicts.delete_if do |_name, conflict|
          deps = conflict.requirement_trees.map(&:last).flatten(1)
          !Bundler::VersionRanges.empty?(*Bundler::VersionRanges.for_many(deps.map(&:requirement)))
        end
      end

      e = Molinillo::VersionConflict.new(conflicts, e.specification_provider) unless conflicts.empty?

      solver_name = "Bundler"
      possibility_type = "gem"
      e.message_with_trees(
        :solver_name => solver_name,
        :possibility_type => possibility_type,
        :reduce_trees => lambda do |trees|
          # called first, because we want to reduce the amount of work required to find maximal empty sets
          trees = trees.uniq {|t| t.flatten.map {|dep| [dep.name, dep.requirement] } }

          # bail out if tree size is too big for Array#combination to make any sense
          return trees if trees.size > 15
          maximal = 1.upto(trees.size).map do |size|
            trees.map(&:last).flatten(1).combination(size).to_a
          end.flatten(1).select do |deps|
            Bundler::VersionRanges.empty?(*Bundler::VersionRanges.for_many(deps.map(&:requirement)))
          end.min_by(&:size)

          trees.reject! {|t| !maximal.include?(t.last) } if maximal

          trees.sort_by {|t| t.reverse.map(&:name) }
        end,
        :printable_requirement => lambda {|req| SharedHelpers.pretty_dependency(req) },
        :additional_message_for_conflict => lambda do |o, name, conflict|
          if name == "bundler"
            o << %(\n  Current Bundler version:\n    bundler (#{Bundler::VERSION}))

            conflict_dependency = conflict.requirement
            conflict_requirement = conflict_dependency.requirement
            other_bundler_required = !conflict_requirement.satisfied_by?(Gem::Version.new(Bundler::VERSION))

            if other_bundler_required
              o << "\n\n"

              candidate_specs = source_for(:default_bundler).specs.search(conflict_dependency)
              if candidate_specs.any?
                target_version = candidate_specs.last.version
                new_command = [File.basename($PROGRAM_NAME), "_#{target_version}_", *ARGV].join(" ")
                o << "Your bundle requires a different version of Bundler than the one you're running.\n"
                o << "Install the necessary version with `gem install bundler:#{target_version}` and rerun bundler using `#{new_command}`\n"
              else
                o << "Your bundle requires a different version of Bundler than the one you're running, and that version could not be found.\n"
              end
            end
          elsif conflict.locked_requirement
            o << "\n"
            o << %(Running `bundle update` will rebuild your snapshot from scratch, using only\n)
            o << %(the gems in your Gemfile, which may resolve the conflict.\n)
          elsif !conflict.existing
            o << "\n"

            relevant_source = conflict.requirement.source || source_for(name)

            metadata_requirement = name.end_with?("\0")

            extra_message = if conflict.requirement_trees.first.size > 1
              ", which is required by gem '#{SharedHelpers.pretty_dependency(conflict.requirement_trees.first[-2])}',"
            else
              ""
            end

            if metadata_requirement
              o << "#{SharedHelpers.pretty_dependency(conflict.requirement)}#{extra_message} is not available in #{relevant_source}"
            else
              o << gem_not_found_message(name, conflict.requirement, relevant_source, extra_message)
            end
          end
        end,
        :version_for_spec => lambda {|spec| spec.version },
        :incompatible_version_message_for_conflict => lambda do |name, _conflict|
          if name.end_with?("\0")
            %(#{solver_name} found conflicting requirements for the #{name} version:)
          else
            %(#{solver_name} could not find compatible versions for #{possibility_type} "#{name}":)
          end
        end
      )
    end
  end
end
