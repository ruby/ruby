#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems/version'

##
# Requirement version includes a prefaced comparator in addition
# to a version number.
#
# A Requirement object can actually contain multiple, er,
# requirements, as in (> 1.2, < 2.0).
class Gem::Requirement

  include Comparable

  OPS = {
    "="  =>  lambda { |v, r| v == r },
    "!=" =>  lambda { |v, r| v != r },
    ">"  =>  lambda { |v, r| v > r },
    "<"  =>  lambda { |v, r| v < r },
    ">=" =>  lambda { |v, r| v >= r },
    "<=" =>  lambda { |v, r| v <= r },
    "~>" =>  lambda { |v, r| v >= r && v < r.bump }
  }

  OP_RE = /#{OPS.keys.map{ |k| Regexp.quote k }.join '|'}/o

  ##
  # Factory method to create a Gem::Requirement object.  Input may be a
  # Version, a String, or nil.  Intended to simplify client code.
  #
  # If the input is "weird", the default version requirement is returned.
  #
  def self.create(input)
    case input
    when Gem::Requirement then
      input
    when Gem::Version, Array then
      new input
    else
      if input.respond_to? :to_str then
        self.new [input.to_str]
      else
        self.default
      end
    end
  end

  ##
  # A default "version requirement" can surely _only_ be '>= 0'.
  #--
  # This comment once said:
  #
  # "A default "version requirement" can surely _only_ be '> 0'."
  def self.default
    self.new ['>= 0']
  end

  ##
  # Constructs a Requirement from +requirements+ which can be a String, a
  # Gem::Version, or an Array of those.  See parse for details on the
  # formatting of requirement strings.
  def initialize(requirements)
    @requirements = case requirements
                    when Array then
                      requirements.map do |requirement|
                        parse(requirement)
                      end
                    else
                      [parse(requirements)]
                    end
    @version = nil   # Avoid warnings.
  end

  # Marshal raw requirements, rather than the full object
  def marshal_dump
    [@requirements]
  end

  # Load custom marshal format
  def marshal_load(array)
    @requirements = array[0]
    @version = nil
  end

  def to_s # :nodoc:
    as_list.join(", ")
  end

  def as_list
    normalize
    @requirements.collect { |req|
      "#{req[0]} #{req[1]}"
    }
  end

  def normalize
    return if not defined? @version or @version.nil?
    @requirements = [parse(@version)]
    @nums = nil
    @version = nil
    @op = nil
  end

  ##
  # Is the requirement satifised by +version+.
  #
  # version:: [Gem::Version] the version to compare against
  # return:: [Boolean] true if this requirement is satisfied by
  #          the version, otherwise false
  #
  def satisfied_by?(version)
    normalize
    @requirements.all? { |op, rv| satisfy?(op, version, rv) }
  end

  ##
  # Is "version op required_version" satisfied?
  #
  def satisfy?(op, version, required_version)
    OPS[op].call(version, required_version)
  end

  ##
  # Parse the version requirement obj returning the operator and version.
  #
  # The requirement can be a String or a Gem::Version.  A String can be an
  # operator (<, <=, =, =>, >, !=, ~>), a version number, or both, operator
  # first.
  def parse(obj)
    case obj
    when /^\s*(#{OP_RE})\s*([0-9.]+)\s*$/o then
      [$1, Gem::Version.new($2)]
    when /^\s*([0-9.]+)\s*$/ then
      ['=', Gem::Version.new($1)]
    when /^\s*(#{OP_RE})\s*$/o then
      [$1, Gem::Version.new('0')]
    when Gem::Version then
      ['=', obj]
    else
      fail ArgumentError, "Illformed requirement [#{obj.inspect}]"
    end
  end

  def <=>(other)
    to_s <=> other.to_s
  end

  def hash # :nodoc:
    to_s.hash
  end

end

