# frozen_string_literal: true
##
#
# Represents a gem of name +name+ at +version+ of +platform+. These
# wrap the data returned from the indexes.

class Gem::NameTuple
  def initialize(name, version, platform="ruby")
    @name = name
    @version = version

    unless platform.kind_of? Gem::Platform
      platform = "ruby" if !platform or platform.empty?
    end

    @platform = platform
  end

  attr_reader :name, :version, :platform

  ##
  # Turn an array of [name, version, platform] into an array of
  # NameTuple objects.

  def self.from_list(list)
    list.map {|t| new(*t) }
  end

  ##
  # Turn an array of NameTuple objects back into an array of
  # [name, version, platform] tuples.

  def self.to_basic(list)
    list.map {|t| t.to_a }
  end

  ##
  # A null NameTuple, ie name=nil, version=0

  def self.null
    new nil, Gem::Version.new(0), nil
  end

  ##
  # Returns the full name (name-version) of this Gem.  Platform information is
  # included if it is not the default Ruby platform.  This mimics the behavior
  # of Gem::Specification#full_name.

  def full_name
    case @platform
    when nil, 'ruby', ''
      "#{@name}-#{@version}"
    else
      "#{@name}-#{@version}-#{@platform}"
    end.dup.tap(&Gem::UNTAINT)
  end

  ##
  # Indicate if this NameTuple matches the current platform.

  def match_platform?
    Gem::Platform.match_gem? @platform, @name
  end

  ##
  # Indicate if this NameTuple is for a prerelease version.
  def prerelease?
    @version.prerelease?
  end

  ##
  # Return the name that the gemspec file would be

  def spec_name
    "#{full_name}.gemspec"
  end

  ##
  # Convert back to the [name, version, platform] tuple

  def to_a
    [@name, @version, @platform]
  end

  def inspect # :nodoc:
    "#<Gem::NameTuple #{@name}, #{@version}, #{@platform}>"
  end

  alias to_s inspect # :nodoc:

  def <=>(other)
    [@name, @version, @platform == Gem::Platform::RUBY ? -1 : 1] <=>
      [other.name, other.version,
       other.platform == Gem::Platform::RUBY ? -1 : 1]
  end

  include Comparable

  ##
  # Compare with +other+. Supports another NameTuple or an Array
  # in the [name, version, platform] format.

  def ==(other)
    case other
    when self.class
      @name == other.name and
        @version == other.version and
        @platform == other.platform
    when Array
      to_a == other
    else
      false
    end
  end

  alias_method :eql?, :==

  def hash
    to_a.hash
  end
end
