#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
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
# part in the Nth part sort less than versions with N-1 parts. Prerelease
# parts are sorted alphabetically using the normal Ruby string sorting
# rules.
#
# Prereleases sort between real releases (newest to oldest):
#
# 1. 1.0
# 2. 1.0.b
# 3. 1.0.a
# 4. 0.9

class Gem::Version

  class Part
    include Comparable

    attr_reader :value

    def initialize(value)
      @value = (value =~ /\A\d+\z/) ? value.to_i : value
    end

    def to_s
      self.value.to_s
    end

    def inspect
      @value
    end

    def alpha?
      String === value
    end

    def numeric?
      Fixnum === value
    end

    def <=>(other)
      if    self.numeric? && other.alpha? then
        1
      elsif self.alpha? && other.numeric? then
        -1
      else
        self.value <=> other.value
      end
    end

    def succ
      self.class.new(self.value.succ)
    end
  end

  include Comparable

  VERSION_PATTERN = '[0-9]+(\.[0-9a-z]+)*'

  attr_reader :version

  def self.correct?(version)
    pattern = /\A\s*(#{VERSION_PATTERN})*\s*\z/

    version.is_a? Integer or
      version =~ pattern or
      version.to_s =~ pattern
  end

  ##
  # Factory method to create a Version object.  Input may be a Version or a
  # String.  Intended to simplify client code.
  #
  #   ver1 = Version.create('1.3.17')   # -> (Version object)
  #   ver2 = Version.create(ver1)       # -> (ver1)
  #   ver3 = Version.create(nil)        # -> nil

  def self.create(input)
    if input.respond_to? :version then
      input
    elsif input.nil? then
      nil
    else
      new input
    end
  end

  ##
  # Constructs a Version from the +version+ string.  A version string is a
  # series of digits or ASCII letters separated by dots.

  def initialize(version)
    raise ArgumentError, "Malformed version number string #{version}" unless
      self.class.correct?(version)

    self.version = version
  end

  def inspect # :nodoc:
    "#<#{self.class} #{@version.inspect}>"
  end

  ##
  # Dump only the raw version string, not the complete object

  def marshal_dump
    [@version]
  end

  ##
  # Load custom marshal format

  def marshal_load(array)
    self.version = array[0]
  end

  def parts
    @parts ||= normalize
  end

  ##
  # Strip ignored trailing zeros.

  def normalize
    parts_arr = parse_parts_from_version_string
    if parts_arr.length != 1
      parts_arr.pop while parts_arr.last && parts_arr.last.value == 0
      parts_arr = [Part.new(0)] if parts_arr.empty?
    end
    parts_arr
  end

  ##
  # Returns the text representation of the version

  def to_s
    @version
  end

  def to_yaml_properties
    ['@version']
  end

  def version=(version)
    @version = version.to_s.strip
    normalize
  end

  ##
  # A version is considered a prerelease if any part contains a letter.

  def prerelease?
    parts.any? { |part| part.alpha? }
  end
  
  ##
  # The release for this version (e.g. 1.2.0.a -> 1.2.0)
  # Non-prerelease versions return themselves
  def release
    return self unless prerelease?
    rel_parts = parts.dup
    rel_parts.pop while rel_parts.any? { |part| part.alpha? }
    self.class.new(rel_parts.join('.'))
  end

  def yaml_initialize(tag, values)
    self.version = values['version']
  end

  ##
  # Compares this version with +other+ returning -1, 0, or 1 if the other
  # version is larger, the same, or smaller than this one.

  def <=>(other)
    return nil unless self.class === other
    return 1 unless other
    mine, theirs = balance(self.parts.dup, other.parts.dup)
    mine <=> theirs
  end

  def balance(a, b)
    a << Part.new(0) while a.size < b.size
    b << Part.new(0) while b.size < a.size
    [a, b]
  end

  ##
  # A Version is only eql? to another version if it has the same version
  # string.  "1.0" is not the same version as "1".

  def eql?(other)
    self.class === other and @version == other.version
  end

  def hash # :nodoc:
    @version.hash
  end

  ##
  # Return a new version object where the next to the last revision number is
  # one greater. (e.g.  5.3.1 => 5.4)
  #
  # Pre-release (alpha) parts are ignored. (e.g 5.3.1.b2 => 5.4)

  def bump
    parts = parse_parts_from_version_string
    parts.pop while parts.any? { |part| part.alpha? }
    parts.pop if parts.size > 1
    parts[-1] = parts[-1].succ
    self.class.new(parts.join("."))
  end

  def parse_parts_from_version_string # :nodoc:
    @version.to_s.scan(/[0-9a-z]+/i).map { |s| Part.new(s) }
  end

  def pretty_print(q) # :nodoc:
    q.text "Gem::Version.new(#{@version.inspect})"
  end

  #:stopdoc:

  require 'rubygems/requirement'

  ##
  # Gem::Requirement's original definition is nested in Version.
  # Although an inappropriate place, current gems specs reference the nested
  # class name explicitly.  To remain compatible with old software loading
  # gemspecs, we leave a copy of original definition in Version, but define an
  # alias Gem::Requirement for use everywhere else.

  Requirement = ::Gem::Requirement

  # :startdoc:

end

