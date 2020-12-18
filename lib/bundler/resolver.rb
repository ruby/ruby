# frozen_string_literal: true

module Bundler
  class Resolver
    require_relative "vendored_molinillo"
    require_relative "resolver/spec_group"

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
    def self.resolve(requirements, index, source_requirements = {}, base = [], gem_version_promoter = GemVersionPromoter.new, additional_base_requirements = [], platforms = nil)
      platforms = Set.new(platforms) if platforms
      base = SpecSet.new(base) unless base.is_a?(SpecSet)
      resolver = new(index, source_requirements, base, gem_version_promoter, additional_base_requirements, platforms)
      result = resolver.start(requirements)
      SpecSet.new(result)
    end

    def initialize(index, source_requirements, base, gem_version_promoter, additional_base_requirements, platforms)
      @index = index
      @source_requirements = source_requirements
      @base = base
      @resolver = Molinillo::Resolver.new(self, self)
      @search_for = {}
      @base_dg = Molinillo::DependencyGraph.new
      @base.each do |ls|
        dep = Dependency.new(ls.name, ls.version)
        @base_dg.add_vertex(ls.name, DepProxy.new(dep, ls.platform), true)
      end
      additional_base_requirements.each {|d| @base_dg.add_vertex(d.name, d) }
      @platforms = platforms
      @gem_version_promoter = gem_version_promoter
      @allow_bundler_dependency_conflicts = Bundler.feature_flag.allow_bundler_dependency_conflicts?
      @use_gvp = Bundler.feature_flag.use_gem_version_promoter_for_major_updates? || !@gem_version_promoter.major?
      @lockfile_uses_separate_rubygems_sources = Bundler.feature_flag.disable_multisource?
    end

    def start(requirements)
      @gem_version_promoter.prerelease_specified = @prerelease_specified = {}
      requirements.each {|dep| @prerelease_specified[dep.name] ||= dep.prerelease? }

      verify_gemfile_dependencies_are_found!(requirements)
      dg = @resolver.resolve(requirements, @base_dg)
      dg.
        tap {|resolved| validate_resolved_specs!(resolved) }.
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
      puts debug_info.split("\n").map {|s| "BUNDLER: " + "  " * depth + s }
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
      @search_for[dependency_proxy] ||= begin
        name = dependency.name
        index = index_for(dependency)
        results = index.search(dependency, @base[name])

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
            spec_group = SpecGroup.new(specs)
            spec_group.ignores_bundler_dependencies = @allow_bundler_dependency_conflicts
            groups << spec_group
          end
        else
          []
        end
        # GVP handles major itself, but it's still a bit risky to trust it with it
        # until we get it settled with new behavior. For 2.x it can take over all cases.
        search = if !@use_gvp
          spec_groups
        else
          @gem_version_promoter.sort_versions(dependency, spec_groups)
        end
        selected_sgs = []
        search.each do |sg|
          next unless sg.for?(platform)
          sg_all_platforms = sg.copy_for(self.class.sort_platforms(@platforms).reverse)
          selected_sgs << sg_all_platforms

          next if sg_all_platforms.activated_platforms == [Gem::Platform::RUBY]
          # Add a spec group for "non platform specific spec" as the fallback
          # spec group.
          sg_ruby = sg.copy_for([Gem::Platform::RUBY])
          selected_sgs.insert(-2, sg_ruby) if sg_ruby
        end
        selected_sgs
      end
    end

    def index_for(dependency)
      source = @source_requirements[dependency.name]
      if source
        source.specs
      elsif @lockfile_uses_separate_rubygems_sources
        Index.build do |idx|
          if dependency.all_sources
            dependency.all_sources.each {|s| idx.add_source(s.specs) if s }
          else
            idx.add_source @source_requirements[:default].specs
          end
        end
      else
        @index
      end
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

    def relevant_sources_for_vertex(vertex)
      if vertex.root?
        [@source_requirements[vertex.name]]
      elsif @lockfile_uses_separate_rubygems_sources
        vertex.recursive_predecessors.map do |v|
          @source_requirements[v.name]
        end << @source_requirements[:default]
      end
    end

    def sort_dependencies(dependencies, activated, conflicts)
      dependencies.sort_by do |dependency|
        dependency.all_sources = relevant_sources_for_vertex(activated.vertex_named(dependency.name))
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

    # Sort platforms from most general to most specific
    def self.sort_platforms(platforms)
      platforms.sort_by do |platform|
        platform_sort_key(platform)
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

        cache_message = begin
                            " or in gems cached in #{Bundler.settings.app_cache_path}" if Bundler.app_cache.exist?
                          rescue GemfileNotFound
                            nil
                          end

        if (base = @base[name]) && !base.empty?
          version = base.first.version
          message = "You have requested:\n" \
            "  #{name} #{requirement.requirement}\n\n" \
            "The bundle currently has #{name} locked at #{version}.\n" \
            "Try running `bundle update #{name}`\n\n" \
            "If you are updating multiple gems in your Gemfile at once,\n" \
            "try passing them all to `bundle update`"
        elsif source = @source_requirements[name]
          specs = source.specs[name]
          versions_with_platforms = specs.map {|s| [s.version, s.platform] }
          message = String.new("Could not find gem '#{SharedHelpers.pretty_dependency(requirement)}' in #{source}#{cache_message}.\n")
          message << if versions_with_platforms.any?
            "The source contains the following versions of '#{name}': #{formatted_versions_with_platforms(versions_with_platforms)}"
          else
            "The source does not contain any versions of '#{name}'"
          end
        else
          message = "Could not find gem '#{requirement}' in any of the gem sources " \
            "listed in your Gemfile#{cache_message}."
        end
        raise GemNotFound, message
      end
    end

    def formatted_versions_with_platforms(versions_with_platforms)
      version_platform_strs = versions_with_platforms.map do |vwp|
        version = vwp.first
        platform = vwp.last
        version_platform_str = String.new(version.to_s)
        version_platform_str << " #{platform}" unless platform.nil? || platform == Gem::Platform::RUBY
        version_platform_str
      end
      version_platform_strs.join(", ")
    end

    def version_conflict_message(e)
      # only show essential conflicts, if possible
      conflicts = e.conflicts.dup
      conflicts.delete_if do |_name, conflict|
        deps = conflict.requirement_trees.map(&:last).flatten(1)
        !Bundler::VersionRanges.empty?(*Bundler::VersionRanges.for_many(deps.map(&:requirement)))
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
            other_bundler_required = !conflict.requirement.requirement.satisfied_by?(Gem::Version.new(Bundler::VERSION))
          end

          if name == "bundler" && other_bundler_required
            o << "\n"
            o << "This Gemfile requires a different version of Bundler.\n"
            o << "Perhaps you need to update Bundler by running `gem install bundler`?\n"
          end
          if conflict.locked_requirement
            o << "\n"
            o << %(Running `bundle update` will rebuild your snapshot from scratch, using only\n)
            o << %(the gems in your Gemfile, which may resolve the conflict.\n)
          elsif !conflict.existing
            o << "\n"

            relevant_sources = if conflict.requirement.source
              [conflict.requirement.source]
            elsif conflict.requirement.all_sources
              conflict.requirement.all_sources
            elsif @lockfile_uses_separate_rubygems_sources
              # every conflict should have an explicit group of sources when we
              # enforce strict pinning
              raise "no source set for #{conflict}"
            else
              []
            end.compact.map(&:to_s).uniq.sort

            metadata_requirement = name.end_with?("\0")

            o << "Could not find gem '" unless metadata_requirement
            o << SharedHelpers.pretty_dependency(conflict.requirement)
            o << "'" unless metadata_requirement
            if conflict.requirement_trees.first.size > 1
              o << ", which is required by "
              o << "gem '#{SharedHelpers.pretty_dependency(conflict.requirement_trees.first[-2])}',"
            end
            o << " "

            o << if relevant_sources.empty?
              "in any of the sources.\n"
            elsif metadata_requirement
              "is not available in #{relevant_sources.join(" or ")}"
            else
              "in any of the relevant sources:\n  #{relevant_sources * "\n  "}\n"
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

    def validate_resolved_specs!(resolved_specs)
      resolved_specs.each do |v|
        name = v.name
        next unless sources = relevant_sources_for_vertex(v)
        sources.compact!
        if default_index = sources.index(@source_requirements[:default])
          sources.delete_at(default_index)
        end
        sources.reject! {|s| s.specs[name].empty? }
        sources.uniq!
        next if sources.size <= 1

        multisource_disabled = Bundler.feature_flag.disable_multisource?

        msg = ["The gem '#{name}' was found in multiple relevant sources."]
        msg.concat sources.map {|s| "  * #{s}" }.sort
        msg << "You #{multisource_disabled ? :must : :should} add this gem to the source block for the source you wish it to be installed from."
        msg = msg.join("\n")

        raise SecurityError, msg if multisource_disabled
        Bundler.ui.warn "Warning: #{msg}"
      end
    end
  end
end
