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

    @all_specs = Hash.new {|h, name| h[name] = find_all_specs_for(name) }
    @all_versions = Hash.new {|h, pkg| h[pkg] = @all_specs[pkg.to_s].map(&:version).uniq.sort }
    @sorted_versions = Hash.new {|h, pkg| h[pkg] = filter_versions(pkg) }
    @cached_dependencies = Hash.new {|h, pkg| h[pkg] = Hash.new {|v, ver| v[ver] = compute_dependencies(pkg, ver) } }
    @version_to_index = Hash.new {|h, pkg| h[pkg] = @sorted_versions[pkg].each_with_index.to_h }
    @versions_for_cache = {}
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

      if matching.empty?
        exc = Gem::UnsatisfiableDependencyError.new(dep_request, all)
        exc.errors = @set.errors
        raise exc
      end

      specs_matching_requirement = matching.select {|s| dep.requirement.satisfied_by?(s.version) }
      next unless specs_matching_requirement.empty?
      exc = Gem::UnsatisfiableDependencyError.new(dep_request, all)
      exc.errors = @set.errors
      raise exc
    end

    # Build root deps from @needed
    root_deps = {}
    @needed.each do |dep|
      range = Gem::PubGrub::RubyGems.requirement_to_range(dep.requirement)
      constraint = Gem::PubGrub::VersionConstraint.new(package_for(dep.name), range: range)
      root_deps[dep.name] = root_deps.key?(dep.name) ? root_deps[dep.name].intersect(constraint) : constraint
    end

    @sorted_versions[@root_package] = [@root_version]
    @cached_dependencies[@root_package] = { @root_version => root_deps }

    solver = Gem::PubGrub::VersionSolver.new(
      source: self,
      root: @root_package,
      strategy: Gem::Resolver::Strategy.new(self, @root_package),
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
    return [@root_version] if package == @root_package

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
    @versions_for_cache[[package, range]] ||= range.select_versions(@sorted_versions[package])
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

      if dep_constraint.range.empty?
        cause = Gem::PubGrub::Incompatibility::InvalidDependency.new(dep_package, dep_constraint)
        next Gem::PubGrub::Incompatibility.new(
          [Gem::PubGrub::Term.new(self_constraint, true)],
          cause: cause
        )
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

  # Filter versions to exclude prereleases unless prerelease is enabled.
  # Both all_versions_for and versions_for use this filtered set to ensure
  # PubGrub's constraint propagation and version selection are consistent.
  def filter_versions(package)
    all_versions = @all_versions[package]
    if @set.respond_to?(:prerelease) && @set.prerelease
      all_versions
    else
      stable = all_versions.reject(&:prerelease?)
      stable.empty? ? all_versions : stable
    end
  end

  def find_all_specs_for(name)
    dep = Gem::Dependency.new(name, ">= 0.a")
    dep_request = DependencyRequest.new(dep, nil)
    all = @set.find_all(dep_request)

    specs = select_local_platforms(all)

    unless @soft_missing
      specs = specs.select do |s|
        actual = s.respond_to?(:spec) ? s.spec : s
        actual.required_ruby_version.satisfied_by?(Gem.ruby_version) &&
          actual.required_rubygems_version.satisfied_by?(Gem.rubygems_version)
      rescue StandardError
        true
      end
    end

    specs
  end

  def spec_for(name, version)
    candidates = @all_specs[name].select {|s| s.version == version }

    if candidates.length > 1
      # Prefer already-installed specs to avoid unnecessary downloads
      installed = candidates.select {|s| s.is_a?(Gem::Resolver::InstalledSpecification) }
      return installed.first if installed.length == 1
      candidates = installed if installed.any?

      # Among remaining candidates, prefer the most specific platform
      candidates.min_by {|s| Gem::Platform.platform_specificity_match(s.platform, Gem::Platform.local) }
    else
      candidates.first
    end
  end

  def compute_dependencies(package, version)
    return {} if package == @root_package

    spec = spec_for(package.to_s, version)
    return {} unless spec
    return {} if @ignore_dependencies

    deps = {}
    root_names = @needed.map(&:name)

    actual_spec = spec.respond_to?(:spec) ? spec.spec : spec
    actual_spec.dependencies.each do |d|
      next if d.name == package.to_s
      next if d.type == :development && !@development
      next if d.type == :development && @development_shallow && !root_names.include?(package.to_s)

      dep_package = package_for(d.name)

      # Check if the dependency has any available versions
      dep_specs = @all_specs[d.name]
      if dep_specs.empty? && @soft_missing
        next
      end

      range = Gem::PubGrub::RubyGems.requirement_to_range(d.requirement)
      deps[d.name] = Gem::PubGrub::VersionConstraint.new(dep_package, range: range)
    end

    deps
  end

  def build_extended_explanation(name, constraint)
    dep = Gem::Dependency.new(name, ">= 0.a")
    dep_request = DependencyRequest.new(dep, nil)
    unfiltered = @set.find_all(dep_request)
    return if unfiltered.empty?

    filtered = @all_specs[name]
    return if filtered.length == unfiltered.length

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
