# frozen_string_literal: true
module Bundler
  class Resolver
    require "bundler/vendored_molinillo"

    class Molinillo::VersionConflict
      def printable_dep(dep)
        if dep.is_a?(Bundler::Dependency)
          DepProxy.new(dep, dep.platforms.join(", ")).to_s.strip
        else
          dep.to_s
        end
      end

      def message
        conflicts.sort.reduce(String.new) do |o, (name, conflict)|
          o << %(\nBundler could not find compatible versions for gem "#{name}":\n)
          if conflict.locked_requirement
            o << %(  In snapshot (#{Bundler.default_lockfile.basename}):\n)
            o << %(    #{printable_dep(conflict.locked_requirement)}\n)
            o << %(\n)
          end
          o << %(  In Gemfile:\n)
          trees = conflict.requirement_trees

          maximal = 1.upto(trees.size).map do |size|
            trees.map(&:last).flatten(1).combination(size).to_a
          end.flatten(1).select do |deps|
            Bundler::VersionRanges.empty?(*Bundler::VersionRanges.for_many(deps.map(&:requirement)))
          end.min_by(&:size)
          trees.reject! {|t| !maximal.include?(t.last) } if maximal

          o << trees.sort_by {|t| t.reverse.map(&:name) }.map do |tree|
            t = String.new
            depth = 2
            tree.each do |req|
              t << "  " * depth << req.to_s
              unless tree.last == req
                if spec = conflict.activated_by_name[req.name]
                  t << %( was resolved to #{spec.version}, which)
                end
                t << %( depends on)
              end
              t << %(\n)
              depth += 1
            end
            t
          end.join("\n")

          if name == "bundler"
            o << %(\n  Current Bundler version:\n    bundler (#{Bundler::VERSION}))
            other_bundler_required = !conflict.requirement.requirement.satisfied_by?(Gem::Version.new Bundler::VERSION)
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
            if conflict.requirement_trees.first.size > 1
              o << "Could not find gem '#{conflict.requirement}', which is required by "
              o << "gem '#{conflict.requirement_trees.first[-2]}', in any of the sources."
            else
              o << "Could not find gem '#{conflict.requirement}' in any of the sources\n"
            end
          end
          o
        end.strip
      end
    end

    class SpecGroup < Array
      include GemHelpers

      attr_reader :activated

      def initialize(a)
        super
        @required_by = []
        @activated_platforms = []
        @dependencies = nil
        @specs        = Hash.new do |specs, platform|
          specs[platform] = select_best_platform_match(self, platform)
        end
      end

      def initialize_copy(o)
        super
        @activated_platforms = o.activated.dup
      end

      def to_specs
        @activated_platforms.map do |p|
          next unless s = @specs[p]
          lazy_spec = LazySpecification.new(name, version, s.platform, source)
          lazy_spec.dependencies.replace s.dependencies
          lazy_spec
        end.compact
      end

      def activate_platform!(platform)
        return unless for?(platform)
        return if @activated_platforms.include?(platform)
        @activated_platforms << platform
      end

      def name
        @name ||= first.name
      end

      def version
        @version ||= first.version
      end

      def source
        @source ||= first.source
      end

      def for?(platform)
        spec = @specs[platform]
        !spec.nil?
      end

      def to_s
        "#{name} (#{version})"
      end

      def dependencies_for_activated_platforms
        dependencies = @activated_platforms.map {|p| __dependencies[p] }
        metadata_dependencies = @activated_platforms.map do |platform|
          metadata_dependencies(@specs[platform], platform)
        end
        dependencies.concat(metadata_dependencies).flatten
      end

      def platforms_for_dependency_named(dependency)
        __dependencies.select {|_, deps| deps.map(&:name).include? dependency }.keys
      end

    private

      def __dependencies
        @dependencies = Hash.new do |dependencies, platform|
          dependencies[platform] = []
          if spec = @specs[platform]
            spec.dependencies.each do |dep|
              next if dep.type == :development
              dependencies[platform] << DepProxy.new(dep, platform)
            end
          end
          dependencies[platform]
        end
      end

      def metadata_dependencies(spec, platform)
        return [] unless spec
        # Only allow endpoint specifications since they won't hit the network to
        # fetch the full gemspec when calling required_ruby_version
        return [] if !spec.is_a?(EndpointSpecification) && !spec.is_a?(Gem::Specification)
        dependencies = []
        if !spec.required_ruby_version.nil? && !spec.required_ruby_version.none?
          dependencies << DepProxy.new(Gem::Dependency.new("ruby\0", spec.required_ruby_version), platform)
        end
        if !spec.required_rubygems_version.nil? && !spec.required_rubygems_version.none?
          dependencies << DepProxy.new(Gem::Dependency.new("rubygems\0", spec.required_rubygems_version), platform)
        end
        dependencies
      end
    end

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
    end

    def start(requirements)
      verify_gemfile_dependencies_are_found!(requirements)
      dg = @resolver.resolve(requirements, @base_dg)
      dg.map(&:payload).
        reject {|sg| sg.name.end_with?("\0") }.
        map(&:to_specs).flatten
    rescue Molinillo::VersionConflict => e
      raise VersionConflict.new(e.conflicts.keys.uniq, e.message)
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
      STDERR.puts debug_info.split("\n").map {|s| "  " * depth + s }
    end

    def debug?
      return @debug_mode if defined?(@debug_mode)
      @debug_mode = ENV["DEBUG_RESOLVER"] || ENV["DEBUG_RESOLVER_TREE"] || false
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

    def search_for(dependency)
      platform = dependency.__platform
      dependency = dependency.dep unless dependency.is_a? Gem::Dependency
      search = @search_for[dependency] ||= begin
        index = index_for(dependency)
        results = index.search(dependency, @base[dependency.name])
        if vertex = @base_dg.vertex_named(dependency.name)
          locked_requirement = vertex.payload.requirement
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
            groups << SpecGroup.new(specs)
          end
        else
          []
        end
        # GVP handles major itself, but it's still a bit risky to trust it with it
        # until we get it settled with new behavior. For 2.x it can take over all cases.
        if @gem_version_promoter.major?
          spec_groups
        else
          @gem_version_promoter.sort_versions(dependency, spec_groups)
        end
      end
      search.select {|sg| sg.for?(platform) }.each {|sg| sg.activate_platform!(platform) }
    end

    def index_for(dependency)
      @source_requirements[dependency.name] || @index
    end

    def name_for(dependency)
      dependency.name
    end

    def name_for_explicit_dependency_source
      Bundler.default_gemfile.basename.to_s
    rescue
      "Gemfile"
    end

    def name_for_locking_dependency_source
      Bundler.default_lockfile.basename.to_s
    rescue
      "Gemfile.lock"
    end

    def requirement_satisfied_by?(requirement, activated, spec)
      return false unless requirement.matches_spec?(spec) || spec.source.is_a?(Source::Gemspec)
      spec.activate_platform!(requirement.__platform) if !@platforms || @platforms.include?(requirement.__platform)
      true
    end

    def sort_dependencies(dependencies, activated, conflicts)
      dependencies.sort_by do |dependency|
        name = name_for(dependency)
        [
          @base_dg.vertex_named(name) ? 0 : 1,
          activated.vertex_named(name).payload ? 0 : 1,
          amount_constrained(dependency),
          conflicts[name] ? 0 : 1,
          activated.vertex_named(name).payload ? 0 : search_for(dependency).count,
        ]
      end
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
            search = search_for(dependency).size
            search - all
          end
        end
      end
    end

    def verify_gemfile_dependencies_are_found!(requirements)
      requirements.each do |requirement|
        next if requirement.name == "bundler"
        next unless search_for(requirement).empty?
        if (base = @base[requirement.name]) && !base.empty?
          version = base.first.version
          message = "You have requested:\n" \
            "  #{requirement.name} #{requirement.requirement}\n\n" \
            "The bundle currently has #{requirement.name} locked at #{version}.\n" \
            "Try running `bundle update #{requirement.name}`\n\n" \
            "If you are updating multiple gems in your Gemfile at once,\n" \
            "try passing them all to `bundle update`"
        elsif requirement.source
          name = requirement.name
          specs = @source_requirements[name][name]
          versions_with_platforms = specs.map {|s| [s.version, s.platform] }
          message = String.new("Could not find gem '#{requirement}' in #{requirement.source}.\n")
          message << if versions_with_platforms.any?
                       "Source contains '#{name}' at: #{formatted_versions_with_platforms(versions_with_platforms)}"
                     else
                       "Source does not contain any versions of '#{requirement}'"
                     end
        else
          cache_message = begin
                            " or in gems cached in #{Bundler.settings.app_cache_path}" if Bundler.app_cache.exist?
                          rescue GemfileNotFound
                            nil
                          end
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
        version_platform_str << " #{platform}" unless platform.nil?
      end
      version_platform_strs.join(", ")
    end
  end
end
