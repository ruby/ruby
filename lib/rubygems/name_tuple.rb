# frozen_string_literal: true

##
#
# Represents a gem of name +name+ at +version+ of +platform+, optionally
# carrying a +content_address+ and +ruby_abi+ for content-addressable gems.
# These wrap the data returned from the indexes.

class Gem::NameTuple
  def initialize(name, version, platform = Gem::Platform::RUBY, content_address: nil, ruby_abi: nil)
    @name = name
    @version = version

    platform &&= platform.to_s
    platform = Gem::Platform::RUBY if !platform || platform.empty?
    @platform = platform
    @content_address = content_address unless content_address.nil?
    @ruby_abi = ruby_abi unless ruby_abi.nil?
  end

  attr_reader :name, :version, :platform, :content_address, :ruby_abi

  ##
  # Turn an array of tuples into an array of NameTuple objects. Accepts:
  # * Gem::NameTuple objects (passed through as-is)
  # * 3-element arrays: [name, version, platform]
  # * 5-element arrays: [name, version, platform, content_address, ruby_abi]

  def self.from_list(list)
    list.map do |tuple|
      case tuple
      when Gem::NameTuple
        tuple
      when Array
        case tuple.length
        when 3, 5
          new(tuple[0], tuple[1], tuple[2], content_address: tuple[3], ruby_abi: tuple[4])
        else
          raise ArgumentError, "Expected a 3- or 5-element tuple, got #{tuple.length}"
        end
      else
        raise ArgumentError, "Expected a Gem::NameTuple or Array, got #{tuple.class}"
      end
    end
  end

  ##
  # Turn an array of NameTuple objects back into an array of
  # [name, version, platform] tuples.

  def self.to_basic(list)
    list.map {|tuple| [tuple.name, tuple.version, tuple.platform] }
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
    if @content_address
      "#{@name}-#{@version}-#{@content_address}"
    elsif @platform.nil? || @platform.empty? || @platform == Gem::Platform::RUBY
      "#{@name}-#{@version}"
    else
      "#{@name}-#{@version}-#{@platform}"
    end
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
  # Convert back to the tuple array. Returns [name, version, platform] for
  # non-content-addressable gems, or [name, version, platform, content_address,
  # ruby_abi] for content-addressable gems.

  def to_a
    if @content_address
      [@name, @version, @platform, @content_address, @ruby_abi]
    else
      [@name, @version, @platform]
    end
  end

  alias_method :deconstruct, :to_a

  def deconstruct_keys(keys)
    {
      name: @name,
      version: @version,
      platform: @platform,
      content_address: @content_address,
      ruby_abi: @ruby_abi,
    }
  end

  def inspect # :nodoc:
    "#<Gem::NameTuple name=#{@name} version=#{@version} platform=#{@platform} content_address=#{@content_address} ruby_abi=#{@ruby_abi}>"
  end

  alias_method :to_s, :inspect # :nodoc:

  def <=>(other)
    sort_key <=> other.sort_key
  end

  def sort_key # :nodoc:
    [@name, @version, Gem::Platform.sort_priority(@platform), @content_address.to_s, @ruby_abi.to_s]
  end

  include Comparable

  ##
  # Compare with +other+. Supports another NameTuple or an Array
  # in the [name, version, platform, content_address, ruby_abi] format.

  def ==(other)
    case other
    when self.class
      @name == other.name &&
        @version == other.version &&
        @platform == other.platform &&
        @content_address == other.content_address &&
        @ruby_abi == other.ruby_abi
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
