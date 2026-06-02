# frozen_string_literal: true

require_relative "dependency"
require_relative "exceptions"

##
# Given a set of Gem::Dependency objects as +needed+ and a way to query the
# set of available specs via +set+, calculates a set of ActivationRequest
# objects which indicate all the specs that should be activated to meet the
# all the requirements.

class Gem::Resolver
  require_relative "vendored_pub_grub"

  ##
  # If the DEBUG_RESOLVER environment variable is set then debugging mode is
  # enabled for the resolver.  This will display information about the state
  # of the resolver while a set of dependencies is being resolved.

  DEBUG_RESOLVER = !ENV["DEBUG_RESOLVER"].nil?

  ##
  # Set to true if all development dependencies should be considered.

  attr_accessor :development

  ##
  # Set to true if immediate development dependencies should be considered.

  attr_accessor :development_shallow

  ##
  # When true, no dependencies are looked up for requested gems.

  attr_accessor :ignore_dependencies

  ##
  # Hash of gems to skip resolution.  Keyed by gem name, with arrays of
  # gem specifications as values.

  attr_accessor :skip_gems

  ##
  #

  attr_accessor :soft_missing

  ##
  # Combines +sets+ into a ComposedSet that allows specification lookup in a
  # uniform manner.  If one of the +sets+ is itself a ComposedSet its sets are
  # flattened into the result ComposedSet.

  def self.compose_sets(*sets)
    sets.compact!

    sets = sets.flat_map do |set|
      case set
      when Gem::Resolver::BestSet then
        set
      when Gem::Resolver::ComposedSet then
        set.sets
      else
        set
      end
    end

    case sets.length
    when 0 then
      raise ArgumentError, "one set in the composition must be non-nil"
    when 1 then
      sets.first
    else
      Gem::Resolver::ComposedSet.new(*sets)
    end
  end

  ##
  # Creates a Resolver that queries only against the already installed gems
  # for the +needed+ dependencies.

  def self.for_current_gems(needed)
    new needed, Gem::Resolver::CurrentSet.new
  end

  ##
  # Create Resolver object which will resolve the tree starting
  # with +needed+ Dependency objects.
  #
  # +set+ is an object that provides where to look for specifications to
  # satisfy the Dependencies. This defaults to IndexSet, which will query
  # rubygems.org.

  def initialize(needed, set = nil)
    @set = set || Gem::Resolver::IndexSet.new
    @needed = needed

    @development         = false
    @development_shallow = false
    @ignore_dependencies = false
    @skip_gems           = {}
    @soft_missing        = false

    @root_package = RootPackage.new
    @root_version = Gem::PubGrub::Package.root_version

    @packages = {}

    @unfiltered_specs = Hash.new {|h, name| h[name] = find_unfiltered_specs_for(name) }
    @all_specs = Hash.new {|h, name| h[name] = filter_specs(@unfiltered_specs[name]) }
    @all_versions = Hash.new {|h, pkg| h[pkg] = @all_specs[pkg.to_s].map(&:version).uniq.sort }
    @sorted_versions = Hash.new do |h, pkg|
      h[pkg] = Gem::PubGrub::Package.root?(pkg) ? [@root_version] : @all_versions[pkg]
    end
    @cached_dependencies = Hash.new do |h, pkg|
      h[pkg] = if Gem::PubGrub::Package.root?(pkg)
        { @root_version => root_dependencies }
      else
        Hash.new {|v, ver| v[ver] = compute_dependencies(pkg, ver) }
      end
    end
    @version_to_index = Hash.new {|h, pkg| h[pkg] = @sorted_versions[pkg].each_with_index.to_h }
    @versions_for_cache = Hash.new {|h, pkg| h[pkg] = {} }
    @spec_for_cache = Hash.new {|h, name| h[name] = build_spec_for_cache(name) }
  end

  ##
  # Proceed with resolution! Returns an array of ActivationRequest objects.

  def resolve
    # Pre-check: raise UnsatisfiableDependencyError for root deps with no matches
    @needed.each do |dep|
      next if @soft_missing
      dep_request = DependencyRequest.new(dep, nil)
      all = @set.find_all(dep_request)
      matching = select_local_platforms(all)

      next unless matching.empty?

      exc = Gem::UnsatisfiableDependencyError.new(dep_request, all)
      exc.errors = @set.errors
      raise exc
    end

    solver = Gem::PubGrub::VersionSolver.new(
      source: self,
      root: @root_package,
      strategy: Gem::Resolver::Strategy.new(self),
      logger: make_logger
    )
    result = solver.solve

    # Convert to Array<ActivationRequest>
    needed_by_name = @needed.group_by(&:name)
    result.filter_map do |package, version|
      next if Gem::PubGrub::Package.root?(package)
      spec = spec_for(package.to_s, version)
      dep = needed_by_name[package.to_s]&.first || Gem::Dependency.new(package.to_s)
      dep_request = DependencyRequest.new(dep, nil)
      ActivationRequest.new(spec, dep_request)
    end
  rescue Gem::PubGrub::SolveFailure => e
    extended = extract_extended_explanation(e.incompatibility)
    if extended
      message = "#{e.explanation}\n\n#{extended}"
      raise Gem::DependencyResolutionError, Struct.new(:explanation).new(message)
    else
      raise Gem::DependencyResolutionError, e
    end
  end

  # PubGrub source interface methods

  def all_versions_for(package)
    versions = @sorted_versions[package].reverse # highest first
    name = package.to_s

    if (skip_dep_gems = skip_gems[name]) && !skip_dep_gems.empty?
      skip_versions = skip_dep_gems.map(&:version)
      preferred, rest = versions.partition {|v| skip_versions.include?(v) }
      preferred + rest
    else
      # Prefer already-installed versions to avoid unnecessary upgrades
      installed_versions = @all_specs[name].
        select {|s| s.is_a?(Gem::Resolver::InstalledSpecification) }.
        map(&:version)
      if installed_versions.any?
        preferred, rest = versions.partition {|v| installed_versions.include?(v) }
        preferred + rest
      else
        versions
      end
    end
  end

  def versions_for(package, range = Gem::PubGrub::VersionRange.any)
    @versions_for_cache[package][range] ||= begin
      candidates = range.select_versions(@sorted_versions[package])

      if Gem::PubGrub::Package.root?(package) ||
         (@set.respond_to?(:prerelease) && @set.prerelease) ||
         range_admits_prerelease?(range)
        candidates
      elsif @all_versions[package].any? {|v| !v.prerelease? }
        candidates.reject(&:prerelease?)
      else
        # Only prereleases exist for this gem; fall back to them so
        # dependencies like `>= 1.0` can still be satisfied.
        candidates
      end
    end
  end

  def no_versions_incompatibility_for(_package, unsatisfied_term)
    cause = Gem::PubGrub::Incompatibility::NoVersions.new(unsatisfied_term)

    name = unsatisfied_term.package.to_s
    constraint = unsatisfied_term.constraint
    extended_explanation = build_extended_explanation(name, constraint)

    custom_explanation = if extended_explanation
      "#{constraint} could not be found in any repository"
    end

    Gem::Resolver::Incompatibility.new(
      [unsatisfied_term],
      cause: cause,
      custom_explanation: custom_explanation,
      extended_explanation: extended_explanation
    )
  end

  def incompatibilities_for(package, version)
    package_deps = @cached_dependencies[package]
    sorted_versions = @sorted_versions[package]
    package_deps[version].filter_map do |dep_package_name, dep_constraint|
      dep_package = dep_constraint.package

      low = high = @version_to_index[package][version]

      # find version low such that all >= low share the same dep
      while low > 0 &&
            package_deps[sorted_versions[low - 1]][dep_package_name] == dep_constraint
        low -= 1
      end
      low =
        if low == 0
          nil
        else
          sorted_versions[low]
        end

      # find version high such that all < high share the same dep
      while high < sorted_versions.length &&
            package_deps[sorted_versions[high]][dep_package_name] == dep_constraint
        high += 1
      end
      high =
        if high == sorted_versions.length
          nil
        else
          sorted_versions[high]
        end

      range = Gem::PubGrub::VersionRange.new(min: low, max: high, include_min: !low.nil?)
      self_constraint = Gem::PubGrub::VersionConstraint.new(package, range: range)

      # No specs anywhere means an unknown package. Check @unfiltered_specs, not
      # the filtered set, so a dep filtered out by platform/Ruby/prerelease falls
      # through to NoVersions for proper hints instead. The band-scoped
      # self_constraint lets clean sibling versions still resolve via backtracking.
      if @unfiltered_specs[dep_package_name].empty?
        cause = Gem::PubGrub::Incompatibility::InvalidDependency.new(dep_package, dep_constraint)
        return [Gem::PubGrub::Incompatibility.new(
          [Gem::PubGrub::Term.new(self_constraint, true)],
          cause: cause
        )]
      end

      # An empty range means the requirement is self-contradictory (e.g. `> 2, < 1`).
      if dep_constraint.range.empty?
        return [Gem::Resolver::Incompatibility.new(
          [Gem::PubGrub::Term.new(self_constraint, true)],
          cause: Gem::PubGrub::Incompatibility::NoVersions.new(dep_constraint),
          custom_explanation: "#{dep_package_name} cannot satisfy contradictory requirements #{dep_constraint.constraint_string}"
        )]
      end

      Gem::PubGrub::Incompatibility.new(
        [Gem::PubGrub::Term.new(self_constraint, true), Gem::PubGrub::Term.new(dep_constraint, false)],
        cause: :dependency
      )
    end
  end

  ##
  # Returns the gems in +specs+ that match the local platform.

  def select_local_platforms(specs) # :nodoc:
    specs.select do |spec|
      Gem::Platform.installable? spec
    end
  end

  private

  def package_for(name)
    @packages[name] ||= Gem::PubGrub::Package.new(name)
  end

  def root_dependencies
    deps = {}
    @needed.each do |dep|
      constraint = Gem::PubGrub::RubyGems.requirement_to_constraint(package_for(dep.name), dep.requirement)
      deps[dep.name] = deps.key?(dep.name) ? deps[dep.name].intersect(constraint) : constraint
    end
    deps
  end

  # Only the min bound is inspected: `~>` synthesises a max like `X.A`
  # whose suffix looks prerelease to Gem::Version but is not the user's
  # intent, so checking max would mis-admit prereleases for every `~>`.
  def range_admits_prerelease?(range)
    range.ranges.any? do |r|
      next false if r.empty?
      r.min&.prerelease?
    end
  end

  def find_unfiltered_specs_for(name)
    dep = Gem::Dependency.new(name, ">= 0.a")
    dep_request = DependencyRequest.new(dep, nil)
    @set.find_all(dep_request)
  end

  def filter_specs(specs)
    filtered = select_local_platforms(specs)

    unless @soft_missing
      filtered = filtered.select do |s|
        s.required_ruby_version.satisfied_by?(Gem.ruby_version) &&
          s.required_rubygems_version.satisfied_by?(Gem.rubygems_version)
      rescue StandardError
        true
      end
    end

    filtered
  end

  def spec_for(name, version)
    @spec_for_cache[name][version]
  end

  def build_spec_for_cache(name)
    # Rank sources by the order they were first supplied so that, when multiple
    # sources offer the same version and platform, the earlier source wins.
    source_rank = {}
    @all_specs[name].each do |s|
      source_rank[s.source] ||= source_rank.size
    end

    @all_specs[name].group_by(&:version).transform_values do |candidates|
      next candidates.first if candidates.length == 1

      # Prefer already-installed specs to avoid unnecessary downloads
      installed = candidates.select {|s| s.is_a?(Gem::Resolver::InstalledSpecification) }
      next installed.first if installed.length == 1
      candidates = installed if installed.any?

      # Among remaining candidates, prefer the most specific platform, then the
      # earlier-supplied source.
      candidates.min_by do |s|
        [Gem::Platform.platform_specificity_match(s.platform, Gem::Platform.local),
         source_rank[s.source]]
      end
    end
  end

  def compute_dependencies(package, version)
    spec = spec_for(package.to_s, version)
    return {} unless spec
    return {} if @ignore_dependencies

    spec.fetch_development_dependencies if @development && spec.respond_to?(:fetch_development_dependencies)

    deps = {}
    root_names = @needed.map(&:name)

    spec.dependencies.each do |d|
      next if d.name == package.to_s
      next if d.type == :development && !@development
      next if d.type == :development && @development_shallow && !root_names.include?(package.to_s)

      dep_package = package_for(d.name)

      # In force mode, skip deps that can't be satisfied - either no
      # specs at all, or no specs matching the version requirement.
      if @soft_missing
        dep_specs = @all_specs[d.name]
        matching = dep_specs.select {|s| d.requirement.satisfied_by?(s.version) }
        next if matching.empty?
      end

      deps[d.name] = Gem::PubGrub::RubyGems.requirement_to_constraint(dep_package, d.requirement)
    end

    deps
  end

  def build_extended_explanation(name, constraint)
    unfiltered = @unfiltered_specs[name]
    return if unfiltered.empty?

    filtered = @all_specs[name]
    pkg = package_for(name)

    # A prerelease hint applies when the source would strip prereleases for
    # this constraint (global prerelease flag off and the constraint's range
    # doesn't itself reach into prerelease territory) AND a prerelease of
    # the gem exists somewhere.
    prerelease_gated = !(@set.respond_to?(:prerelease) && @set.prerelease) &&
                       !range_admits_prerelease?(constraint.range)
    has_prerelease_candidate = prerelease_gated &&
                               @all_versions[pkg].any?(&:prerelease?)

    return if filtered.length == unfiltered.length && !has_prerelease_candidate

    hints = []

    # Check for specs that exist for other platforms
    platform_specs = unfiltered.select do |s|
      !Gem::Platform.installable?(s) && constraint.range.include?(s.version)
    end
    if platform_specs.any?
      label = "#{name} (#{constraint.constraint_string})"
      hints << "The source contains the following gems matching '#{label}':"
      platform_specs.each do |s|
        actual = s.respond_to?(:spec) ? s.spec : s
        hints << "  * #{actual.full_name}"
      end
    end

    # Check for specs filtered by Ruby version
    installable = select_local_platforms(unfiltered)
    ruby_specs = installable.select do |s|
      actual = s.respond_to?(:spec) ? s.spec : s
      constraint.range.include?(s.version) &&
        !actual.required_ruby_version.satisfied_by?(Gem.ruby_version)
    rescue StandardError
      false
    end
    if ruby_specs.any?
      versions = ruby_specs.map(&:version).uniq.sort.reverse.first(3)
      sample = ruby_specs.find {|s| s.version == versions.first }
      actual = sample.respond_to?(:spec) ? sample.spec : sample
      ruby_req = actual.required_ruby_version
      hints << "#{name} #{versions.join(", ")} requires Ruby #{ruby_req} (you have #{Gem.ruby_version})"
    end

    # Check for specs filtered by prerelease status
    if prerelease_gated
      prerelease_versions = @all_versions[pkg].select(&:prerelease?)
      if prerelease_versions.any?
        versions = prerelease_versions.sort.reverse.first(3) # limit to avoid cluttering error output
        hints << "#{name} #{versions.join(", ")} are pre-release versions. Use --prerelease to allow pre-release gems."
      end
    end

    hints.empty? ? nil : hints.join("\n")
  end

  def extract_extended_explanation(incompatibility)
    while incompatibility.cause.is_a?(Gem::PubGrub::Incompatibility::ConflictCause)
      cause = incompatibility.cause

      [cause.conflict, cause.other].each do |incompat|
        if incompat.cause.is_a?(Gem::PubGrub::Incompatibility::NoVersions) &&
           incompat.respond_to?(:extended_explanation) &&
           incompat.extended_explanation
          return incompat.extended_explanation
        end
      end

      incompatibility = cause.conflict
    end

    nil
  end

  def make_logger
    DEBUG_RESOLVER ? Gem::PubGrub::StderrLogger.new : Gem::PubGrub::NullLogger.new
  end

  # Custom root package so error messages say "your request depends on..."
  # instead of PubGrub's default "root depends on...".
  class RootPackage < Gem::PubGrub::Package
    def initialize
      super(:root)
    end

    def root?
      true
    end

    def to_s
      "your request"
    end
  end
end

require_relative "resolver/activation_request"
require_relative "resolver/dependency_request"
require_relative "resolver/incompatibility"
require_relative "resolver/strategy"
require_relative "resolver/requirement_list"
require_relative "resolver/set"
require_relative "resolver/api_set"
require_relative "resolver/composed_set"
require_relative "resolver/best_set"
require_relative "resolver/current_set"
require_relative "resolver/git_set"
require_relative "resolver/index_set"
require_relative "resolver/installer_set"
require_relative "resolver/lock_set"
require_relative "resolver/vendor_set"
require_relative "resolver/source_set"

require_relative "resolver/specification"
require_relative "resolver/spec_specification"
require_relative "resolver/api_specification"
require_relative "resolver/git_specification"
require_relative "resolver/index_specification"
require_relative "resolver/installed_specification"
require_relative "resolver/local_specification"
require_relative "resolver/lock_specification"
require_relative "resolver/vendor_specification"
