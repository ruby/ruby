# frozen_string_literal: true

module Bundler
  #
  # This class implements the interface needed by PubGrub for resolution. It is
  # equivalent to the `PubGrub::BasicPackageSource` class provided by PubGrub by
  # default and used by the most simple PubGrub consumers.
  #
  class Resolver
    require_relative "vendored_pub_grub"
    require_relative "resolver/base"
    require_relative "resolver/package"
    require_relative "resolver/candidate"
    require_relative "resolver/incompatibility"
    require_relative "resolver/root"

    include GemHelpers

    def initialize(source_requirements, base, gem_version_promoter, additional_base_requirements)
      @source_requirements = source_requirements
      @base = Resolver::Base.new(base, additional_base_requirements)
      @gem_version_promoter = gem_version_promoter
    end

    def start(requirements, packages, exclude_specs: [])
      exclude_specs.each do |spec|
        remove_from_candidates(spec)
      end

      @requirements = requirements
      @packages = packages

      root, logger = setup_solver

      Bundler.ui.info "Resolving dependencies...", true

      solve_versions(:root => root, :logger => logger)
    end

    def setup_solver
      root = Resolver::Root.new(name_for_explicit_dependency_source)
      root_version = Resolver::Candidate.new(0)

      @all_specs = Hash.new do |specs, name|
        specs[name] = source_for(name).specs.search(name).sort_by {|s| [s.version, s.platform.to_s] }
      end

      @sorted_versions = Hash.new do |candidates, package|
        candidates[package] = if package.root?
          [root_version]
        else
          all_versions_for(package).sort
        end
      end

      root_dependencies = prepare_dependencies(@requirements, @packages)

      @cached_dependencies = Hash.new do |dependencies, package|
        dependencies[package] = if package.root?
          { root_version => root_dependencies }
        else
          Hash.new do |versions, version|
            versions[version] = to_dependency_hash(version.dependencies, @packages)
          end
        end
      end

      logger = Bundler::UI::Shell.new
      logger.level = debug? ? "debug" : "warn"

      [root, logger]
    end

    def solve_versions(root:, logger:)
      solver = PubGrub::VersionSolver.new(:source => self, :root => root, :logger => logger)
      result = solver.solve
      result.map {|package, version| version.to_specs(package) }.flatten.uniq
    rescue PubGrub::SolveFailure => e
      incompatibility = e.incompatibility

      names_to_unlock = []
      extended_explanation = nil

      while incompatibility.conflict?
        cause = incompatibility.cause
        incompatibility = cause.incompatibility

        incompatibility.terms.each do |term|
          name = term.package.name
          names_to_unlock << name if base_requirements[name]

          no_versions_incompat = [cause.incompatibility, cause.satisfier].find {|incompat| incompat.cause.is_a?(PubGrub::Incompatibility::NoVersions) }
          next unless no_versions_incompat

          extended_explanation = no_versions_incompat.extended_explanation
        end
      end

      names_to_unlock.uniq!

      if names_to_unlock.any?
        Bundler.ui.debug "Found conflicts with locked dependencies. Retrying with #{names_to_unlock.join(", ")} unlocked...", true

        @base.unlock_names(names_to_unlock)

        root, logger = setup_solver

        retry
      end

      explanation = e.message

      if extended_explanation
        explanation << "\n\n"
        explanation << extended_explanation
      end

      raise SolveFailure.new(explanation)
    end

    def parse_dependency(package, dependency)
      range = if repository_for(package).is_a?(Source::Gemspec)
        PubGrub::VersionRange.any
      else
        requirement_to_range(dependency)
      end

      PubGrub::VersionConstraint.new(package, :range => range)
    end

    def versions_for(package, range=VersionRange.any)
      versions = range.select_versions(@sorted_versions[package])

      sort_versions(package, versions)
    end

    def no_versions_incompatibility_for(package, unsatisfied_term)
      cause = PubGrub::Incompatibility::NoVersions.new(unsatisfied_term)
      name = package.name
      constraint = unsatisfied_term.constraint
      constraint_string = constraint.constraint_string
      requirements = constraint_string.split(" OR ").map {|req| Gem::Requirement.new(req.split(",")) }

      if name == "bundler"
        custom_explanation = "the current Bundler version (#{Bundler::VERSION}) does not satisfy #{constraint}"
        extended_explanation = bundler_not_found_message(requirements)
      else
        specs_matching_other_platforms = filter_matching_specs(@all_specs[name], requirements)

        platforms_explanation = specs_matching_other_platforms.any? ? " for any resolution platforms (#{package.platforms.join(", ")})" : ""
        custom_explanation = "#{constraint} could not be found in #{repository_for(package)}#{platforms_explanation}"

        label = "#{name} (#{constraint_string})"
        extended_explanation = other_specs_matching_message(specs_matching_other_platforms, label) if specs_matching_other_platforms.any?
      end

      Incompatibility.new([unsatisfied_term], :cause => cause, :custom_explanation => custom_explanation, :extended_explanation => extended_explanation)
    end

    def debug?
      ENV["BUNDLER_DEBUG_RESOLVER"] ||
        ENV["BUNDLER_DEBUG_RESOLVER_TREE"] ||
        ENV["DEBUG_RESOLVER"] ||
        ENV["DEBUG_RESOLVER_TREE"] ||
        false
    end

    def incompatibilities_for(package, version)
      package_deps = @cached_dependencies[package]
      sorted_versions = @sorted_versions[package]
      package_deps[version].map do |dep_package, dep_constraint|
        if package == dep_package
          cause = PubGrub::Incompatibility::CircularDependency.new(dep_package, dep_constraint.constraint_string)
          return [PubGrub::Incompatibility.new([PubGrub::Term.new(dep_constraint, true)], :cause => cause)]
        end

        low = high = sorted_versions.index(version)

        # find version low such that all >= low share the same dep
        while low > 0 && package_deps[sorted_versions[low - 1]][dep_package] == dep_constraint
          low -= 1
        end
        low =
          if low == 0
            nil
          else
            sorted_versions[low]
          end

        # find version high such that all < high share the same dep
        while high < sorted_versions.length && package_deps[sorted_versions[high]][dep_package] == dep_constraint
          high += 1
        end
        high =
          if high == sorted_versions.length
            nil
          else
            sorted_versions[high]
          end

        range = PubGrub::VersionRange.new(:min => low, :max => high, :include_min => true)

        self_constraint = PubGrub::VersionConstraint.new(package, :range => range)

        dep_term = PubGrub::Term.new(dep_constraint, false)
        self_term = PubGrub::Term.new(self_constraint, true)

        custom_explanation = if dep_package.meta? && package.root?
          "current #{dep_package} version is #{dep_constraint.constraint_string}"
        end

        PubGrub::Incompatibility.new([self_term, dep_term], :cause => :dependency, :custom_explanation => custom_explanation)
      end
    end

    def all_versions_for(package)
      name = package.name
      results = (@base[name] + @all_specs[name]).uniq(&:full_name)
      locked_requirement = base_requirements[name]
      results = filter_matching_specs(results, locked_requirement) if locked_requirement

      versions = results.group_by(&:version).reduce([]) do |groups, (version, specs)|
        platform_specs = package.platforms.flat_map {|platform| select_best_platform_match(specs, platform) }
        next groups if platform_specs.empty?

        ruby_specs = select_best_platform_match(specs, Gem::Platform::RUBY)
        groups << Resolver::Candidate.new(version, :specs => ruby_specs) if ruby_specs.any?

        next groups if platform_specs == ruby_specs

        groups << Resolver::Candidate.new(version, :specs => platform_specs)

        groups
      end

      sort_versions(package, versions)
    end

    def source_for(name)
      @source_requirements[name] || @source_requirements[:default]
    end

    def name_for_explicit_dependency_source
      Bundler.default_gemfile.basename.to_s
    rescue StandardError
      "Gemfile"
    end

    def raise_not_found!(package)
      name = package.name
      source = source_for(name)
      specs = @all_specs[name]
      matching_part = name
      requirement_label = SharedHelpers.pretty_dependency(package.dependency)
      cache_message = begin
                          " or in gems cached in #{Bundler.settings.app_cache_path}" if Bundler.app_cache.exist?
                        rescue GemfileNotFound
                          nil
                        end
      specs_matching_requirement = filter_matching_specs(specs, package.dependency.requirement)

      if specs_matching_requirement.any?
        specs = specs_matching_requirement
        matching_part = requirement_label
        platforms = package.platforms
        platform_label = platforms.size == 1 ? "platform '#{platforms.first}" : "platforms '#{platforms.join("', '")}"
        requirement_label = "#{requirement_label}' with #{platform_label}"
      end

      message = String.new("Could not find gem '#{requirement_label}' in #{source}#{cache_message}.\n")

      if specs.any?
        message << "\n#{other_specs_matching_message(specs, matching_part)}"
      end

      raise GemNotFound, message
    end

    private

    def filter_matching_specs(specs, requirements)
      Array(requirements).flat_map do |requirement|
        specs.select {| spec| requirement_satisfied_by?(requirement, spec) }
      end
    end

    def requirement_satisfied_by?(requirement, spec)
      requirement.satisfied_by?(spec.version) || spec.source.is_a?(Source::Gemspec)
    end

    def sort_versions(package, versions)
      if versions.size > 1
        @gem_version_promoter.sort_versions(package, versions).reverse
      else
        versions
      end
    end

    def repository_for(package)
      source_for(package.name)
    end

    def base_requirements
      @base.base_requirements
    end

    def remove_from_candidates(spec)
      @base.delete(spec)
    end

    def prepare_dependencies(requirements, packages)
      to_dependency_hash(requirements, packages).map do |dep_package, dep_constraint|
        name = dep_package.name

        # If a dependency is scoped to a platform different from the current
        # one, we ignore it. However, it may reappear during resolution as a
        # transitive dependency of another package, so we need to reset the
        # package so the proper versions are considered if reintroduced later.
        if dep_package.platforms.empty?
          @packages.delete(name)
          next
        end

        next [dep_package, dep_constraint] if name == "bundler"
        next [dep_package, dep_constraint] unless versions_for(dep_package, dep_constraint.range).empty?
        next unless dep_package.current_platform?

        raise_not_found!(dep_package)
      end.compact.to_h
    end

    def other_specs_matching_message(specs, requirement)
      message = String.new("The source contains the following gems matching '#{requirement}':\n")
      message << specs.map {|s| "  * #{s.full_name}" }.join("\n")
      message
    end

    def requirement_to_range(requirement)
      ranges = requirement.requirements.map do |(op, version)|
        ver = Resolver::Candidate.new(version)

        case op
        when "~>"
          name = "~> #{ver}"
          bump = Resolver::Candidate.new(version.bump.to_s + ".A")
          PubGrub::VersionRange.new(:name => name, :min => ver, :max => bump, :include_min => true)
        when ">"
          PubGrub::VersionRange.new(:min => ver)
        when ">="
          PubGrub::VersionRange.new(:min => ver, :include_min => true)
        when "<"
          PubGrub::VersionRange.new(:max => ver)
        when "<="
          PubGrub::VersionRange.new(:max => ver, :include_max => true)
        when "="
          PubGrub::VersionRange.new(:min => ver, :max => ver, :include_min => true, :include_max => true)
        when "!="
          PubGrub::VersionRange.new(:min => ver, :max => ver, :include_min => true, :include_max => true).invert
        else
          raise "bad version specifier: #{op}"
        end
      end

      ranges.inject(&:intersect)
    end

    def to_dependency_hash(dependencies, packages)
      dependencies.inject({}) do |deps, dep|
        package = packages[dep.name]

        current_req = deps[package]
        new_req = parse_dependency(package, dep.requirement)

        deps[package] = if current_req
          current_req.intersect(new_req)
        else
          new_req
        end

        deps
      end
    end

    def bundler_not_found_message(conflict_dependencies)
      candidate_specs = filter_matching_specs(source_for(:default_bundler).specs.search("bundler"), conflict_dependencies)

      if candidate_specs.any?
        target_version = candidate_specs.last.version
        new_command = [File.basename($PROGRAM_NAME), "_#{target_version}_", *ARGV].join(" ")
        "Your bundle requires a different version of Bundler than the one you're running.\n" \
        "Install the necessary version with `gem install bundler:#{target_version}` and rerun bundler using `#{new_command}`\n"
      else
        "Your bundle requires a different version of Bundler than the one you're running, and that version could not be found.\n"
      end
    end
  end
end
