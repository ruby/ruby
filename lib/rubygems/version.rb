# frozen_string_literal: true

#--
# Workaround for directly loading Gem::Version in some cases
module Gem; end
#++

##
# The Version class processes string versions into comparable
# values. A version string should normally be a series of numbers
# separated by periods. Each part (digits separated by periods) is
# considered its own number, and these are used for sorting. So for
# instance, 3.10 sorts higher than 3.2 because ten is greater than
# two.
#
# If any part contains letters (currently only a-z are supported) then
# that version is considered prerelease. Versions with a prerelease
# part in the Nth part sort less than versions with N-1
# parts. Prerelease parts are sorted alphabetically using the normal
# Ruby string sorting rules. If a prerelease part contains both
# letters and numbers, it will be broken into multiple parts to
# provide expected sort behavior (1.0.a10 becomes 1.0.a.10, and is
# greater than 1.0.a9).
#
# Prereleases sort between real releases (newest to oldest):
#
# 1. 1.0
# 2. 1.0.b1
# 3. 1.0.a.2
# 4. 0.9
#
# If you want to specify a version restriction that includes both prereleases
# and regular releases of 1.x or later versions:
#
#   s.add_dependency 'example', '>= 1.0.0.a'
#
# == How Software Changes
#
# Libraries generally change in 3 ways:
#
# 1. The change is an implementation detail, bug fix, security fix, or
#    optimization, and has no behavioral effect on the software using it.
#
# 2. The change adds new features, and software using those new features is
#    not compatible with previous versions of the library, but software using
#    previous versions of the library is compatible with the change.
#
# 3. The change modifies the public interface of some part of the library in
#    such a way that software that uses that part of the library must be
#    modified to work.
#
# == RubyGems Rational Versioning (the recommended approach)
#
# * Versions shall be represented by three non-negative integers, separated
#   by periods (e.g. 3.1.4).  The first integer is the "major" version
#   number, the second integer is the "minor" version number, and the third
#   integer is the "patch" version number.
#
# * A category 1 change (implementation detail, bug fix, or security fix)
#   will increment the patch number.
#
# * A category 2 change (backwards compatible) will increment the minor
#   version number and reset the patch number.
#
# * A category 3 change (incompatible) will increment the major version number
#   and reset the minor and patch numbers.
#
# * Any "public" release of a gem should have a different version.
#
# == Optimistic Vs. Pessimistic Dependency Versioning
#
# Users expect to be able to specify a version constraint that gives them
# a reasonable expectation that new versions of a library will work with
# their software if the version constraint is true, and not work with their
# software if the version constraint is false.  In other words, the perfect
# system will accept all compatible versions of the library and reject all
# incompatible versions. Unfortunately, there is no perfect system, as you
# cannot predict the future. You can never know whether a future version of
# a library will contain which type of change.
#
# There are two common outlooks on dependency versioning:
#
# 1. Optimistic. This does not set an upper bound on a dependency. It is
#    possible that a future version of a dependency will break the software,
#    and in that case, the dependency version will need to be updated and
#    changes will need to be made.
#
# 2. Pessimistic. This assumes all major version changes of a dependency will
#    break the software, and that patch or minor changes of a dependency will
#    not break the software. If there is a major version of a dependency
#    released, the dependency version must be updated in order to use it, even
#    if no code changes are actually needed.
#
# In general, optimistic versioning is superior to pessimistic versioning.
# Pessimistic versioning is often wrong in both directions. Dependencies can
# release patch or minor versions that contain incompatibilities. One
# common reason is that a security fix may require a backwards-incompatible API
# change. In this case, even though pessimistic versioning was used, it
# didn't even save effort, as you still need to make code changes and adjust
# dependency versions. Similarly, for all but the smallest dependencies, just
# because the dependency made a backwards incompatible change to one interface
# doesn't mean the dependency made a backwards incompatible change to an
# interface that the software is using. It is a common problem that a
# dependency will release a new major version and the software does not require
# any changes in order to use it. In this case, being pessimistic results in
# additional work for no benefit.
#
# When a library uses pessimistic versioning of dependencies, it causes
# significant problems if that library is not diligent about updating
# dependency versions and any library is depending on that library.
# For example:
#
# * Library A is currently on release 1.2.3.
#
# * Library B is at version 2.3.4 and has a pessimistic dependency on
#   library A, using ~> 1.0 (>= 1.0, < 2).
#
# * Library C is at version 3.4.5 and has an optimistic dependency on
#   library A, using >= 1.0.
#
# * Library D has optimistic dependencies on both libraries B and C.
#
# * Library A releases a new major version, 2.0.0, with new features, which
#   is mostly backwards compatible, but does contain some backwards
#   incompatible changes.
#
# * Library B would work with A 2.0.0, but cannot use it due to pessimistic
#   versioning.
#
# * Library C wants to use the new features in the major release of library
#   A to implement its own new features, so it does so, bumps the
#   dependency version of A to >= 2.0, and releases version 3.5.0.
#
# * Library D cannot upgrade to the new version of library C, because it
#   depends on library B, which has a pessimistic dependency on library A.
#
# * Library C releases a security fix patch version 3.5.1 to fix a
#   vulnerability present in all previous versions.
#
# * Library D is now in a terrible situation. It cannot upgrade to library
#   C 3.5.1, as that requires library A > 2.0, because it depends on library
#   B, which requires library A > 1.0, < 2, even though library B would work
#   fine with library A 2.0.0.
#
# This type of situation brought on by pessimistic versioning is unfortunately
# both common and serious in practice.
#
# This is not to say that optimistic versioning never causes a problem.
# However, with optimistic versioning, if there is a problem, it can be solved
# with the addition of a single dependency. For example, continuing the
# previous example:
#
# * Library A releases a new major version, 3.0.0, which makes backwards
#   incompatible changes that break library C.
#
# * Until library C releases an updated version with new changes, library
#   D only needs to set a specific dependency on library A for > 2.0, < 3,
#   until library C is updated to work with the new version of library A.
#
# Both optimistic versioning and pessimistic versioning have problems in
# certain cases. However, it's significantly easier to fix optimistic
# versioning problems than to fix pessimistic versioning problems.
#
# That is not to say that pessimistic versioning is never appropriate. If the
# dependency is a library that adds a single method, where any change resulting
# in a major version bump would probably break a library using it, then using
# pessimistic versioning may be warranted. Additionally, if a dependency has
# already announced or committed backwards incompatible changes that would
# break a library's use of it, then having that library use a pessimistic
# version constraint would likely be warranted. However, outside of
# specific situations, you should avoid using pessimistic versioning, as the
# costs typically exceed the benefits.

class Gem::Version
  include Comparable

  VERSION_PATTERN = '[0-9]+(?>\.[0-9a-zA-Z]+)*(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?' # :nodoc:
  ANCHORED_VERSION_PATTERN = /\A\s*(#{VERSION_PATTERN})?\s*\z/ # :nodoc:
  RADIX_OPT = [9_500, 3_500, 260_000, 22_227, 24].freeze # :nodoc:

  ##
  # A string representation of this Version.

  def version
    @version
  end

  alias_method :to_s, :version

  ##
  # True if the +version+ string matches RubyGems' requirements.

  def self.correct?(version)
    version.nil? || ANCHORED_VERSION_PATTERN.match?(version.to_s)
  end

  ##
  # Factory method to create a Version object. Input may be a Version
  # or a String. Intended to simplify client code.
  #
  #   ver1 = Version.create('1.3.17')   # -> (Version object)
  #   ver2 = Version.create(ver1)       # -> (ver1)

  def self.create(input)
    if self === input # check yourself before you wreck yourself
      input
    else
      new input
    end
  end

  @@all = {}
  @@bump = {}
  @@release = {}

  def self.new(version) # :nodoc:
    return super unless self == Gem::Version

    @@all[version] ||= super
  end

  ##
  # Constructs a Version from the +version+ string.  A version string is a
  # series of digits or ASCII letters separated by dots.

  def initialize(version)
    unless self.class.correct?(version)
      raise ArgumentError, "Malformed version number string #{version}"
    end

    # If version is an empty string convert it to 0
    version = 0 if version.nil? || (version.is_a?(String) && /\A\s*\Z/.match?(version))

    @version = version.to_s

    # optimization to avoid allocation when given an integer, since we know
    # it's to_s won't have any spaces or dashes
    unless version.is_a?(Integer)
      @version = @version.strip
      @version.gsub!("-",".pre.")
    end
    @version = -@version
    @segments = nil
    @sort_key = compute_sort_key
  end

  ##
  # Return a new version object where the next to the last revision
  # number is one greater (e.g., 5.3.1 => 5.4).
  #
  # Pre-release (alpha) parts, e.g, 5.3.1.b.2 => 5.4, are ignored.

  def bump
    @@bump[self] ||= begin
                       segments = self.segments
                       segments.pop while segments.any? {|s| String === s }
                       segments.pop if segments.size > 1

                       segments[-1] = segments[-1].succ
                       self.class.new segments.join(".")
                     end
  end

  ##
  # A Version is only eql? to another version if it's specified to the
  # same precision. Version "1.0" is not the same as version "1".

  def eql?(other)
    self.class === other && @version == other.version
  end

  def hash # :nodoc:
    canonical_segments.hash
  end

  def init_with(coder) # :nodoc:
    yaml_initialize coder.tag, coder.map
  end

  def inspect # :nodoc:
    "#<#{self.class} #{version.inspect}>"
  end

  ##
  # Dump only the raw version string, not the complete object. It's a
  # string for backwards (RubyGems 1.3.5 and earlier) compatibility.

  def marshal_dump
    [@version]
  end

  ##
  # Load custom marshal format. It's a string for backwards (RubyGems
  # 1.3.5 and earlier) compatibility.

  def marshal_load(array)
    string = array[0]
    raise TypeError, "wrong version string" unless string.is_a?(String)

    initialize string
  end

  def yaml_initialize(tag, map) # :nodoc:
    @version = -map["version"]
    @segments = nil
    @hash = nil
  end

  def encode_with(coder) # :nodoc:
    coder.add "version", @version
  end

  ##
  # A version is considered a prerelease if it contains a letter.

  def prerelease?
    unless instance_variable_defined? :@prerelease
      @prerelease = /[a-zA-Z]/.match?(version)
    end
    @prerelease
  end

  def pretty_print(q) # :nodoc:
    q.text "Gem::Version.new(#{version.inspect})"
  end

  ##
  # The release for this version (e.g. 1.2.0.a -> 1.2.0).
  # Non-prerelease versions return themselves.

  def release
    @@release[self] ||= if prerelease?
      segments = self.segments
      segments.pop while segments.any? {|s| String === s }
      self.class.new segments.join(".")
    else
      self
    end
  end

  def segments # :nodoc:
    _segments.dup
  end

  ##
  # A recommended version for use with a >= Requirement.

  def approximate_recommendation
    segments = self.segments

    segments.pop    while segments.any? {|s| String === s }
    segments.pop    while segments.size > 2
    segments.push 0 while segments.size < 2

    recommendation = ">= #{segments.join(".")}"
    recommendation += ".a" if prerelease?
    recommendation
  end

  ##
  # Compares this version with +other+ returning -1, 0, or 1 if the
  # other version is larger, the same, or smaller than this
  # one. +other+ must be an instance of Gem::Version, comparing with
  # other types may raise an exception.

  def <=>(other)
    if Gem::Version === other
      # Fast path for comparison when available.
      if @sort_key && other.sort_key
        return @sort_key <=> other.sort_key
      end

      return 0 if @version == other.version || canonical_segments == other.canonical_segments

      lhsegments = canonical_segments
      rhsegments = other.canonical_segments

      lhsize = lhsegments.size
      rhsize = rhsegments.size
      limit  = (lhsize > rhsize ? rhsize : lhsize)

      i = 0

      while i < limit
        lhs = lhsegments[i]
        rhs = rhsegments[i]
        i += 1

        next      if lhs == rhs
        return -1 if String  === lhs && Numeric === rhs
        return  1 if Numeric === lhs && String  === rhs

        return lhs <=> rhs
      end

      lhs = lhsegments[i]

      if lhs.nil?
        rhs = rhsegments[i]

        while i < rhsize
          return 1 if String === rhs
          return -1 unless rhs.zero?
          rhs = rhsegments[i += 1]
        end
      else
        while i < lhsize
          return -1 if String === lhs
          return 1 unless lhs.zero?
          lhs = lhsegments[i += 1]
        end
      end

      0
    elsif String === other
      return unless self.class.correct?(other)
      self <=> self.class.new(other)
    end
  end

  # remove trailing zeros segments before first letter or at the end of the version
  def canonical_segments
    @canonical_segments ||= begin
      # remove trailing 0 segments, using dot or letter as anchor
      # may leave a trailing dot which will be ignored by partition_segments
      canonical_version = @version.sub(/(?<=[a-zA-Z.])[.0]+\z/, "")
      # remove 0 segments before the first letter in a prerelease version
      canonical_version.sub!(/(?<=\.|\A)[0.]+(?=[a-zA-Z])/, "") if prerelease?
      partition_segments(canonical_version)
    end
  end

  def freeze
    prerelease?
    _segments
    canonical_segments
    super
  end

  protected

  attr_reader :sort_key # :nodoc:

  def compute_sort_key
    return if prerelease?

    segments = canonical_segments
    return if segments.size > 5

    key = 0
    RADIX_OPT.each_with_index do |radix, i|
      seg = segments.fetch(i, 0)
      return nil if seg >= radix
      key = key * radix + seg
    end

    key
  end

  def _segments
    # segments is lazy so it can pick up version values that come from
    # old marshaled versions, which don't go through marshal_load.
    # since this version object is cached in @@all, its @segments should be frozen
    @segments ||= partition_segments(@version)
  end

  def partition_segments(ver)
    ver.scan(/\d+|[a-z]+/i).map! do |s|
      /\A\d/.match?(s) ? s.to_i : -s
    end.freeze
  end
end
