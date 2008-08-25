#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'rubygems'

##
# The Dependency class holds a Gem name and a Gem::Requirement

class Gem::Dependency

  ##
  # Valid dependency types.
  #--
  # When this list is updated, be sure to change
  # Gem::Specification::CURRENT_SPECIFICATION_VERSION as well.

  TYPES = [
    :development,
    :runtime,
  ]

  ##
  # Dependency name or regular expression.

  attr_accessor :name

  ##
  # Dependency type.

  attr_reader :type

  ##
  # Dependent versions.

  attr_writer :version_requirements

  ##
  # Orders dependencies by name only.

  def <=>(other)
    [@name] <=> [other.name]
  end

  ##
  # Constructs a dependency with +name+ and +requirements+.

  def initialize(name, version_requirements, type=:runtime)
    @name = name

    unless TYPES.include? type
      raise ArgumentError, "Valid types are #{TYPES.inspect}, not #{@type.inspect}"
    end

    @type = type

    @version_requirements = Gem::Requirement.create version_requirements
    @version_requirement = nil   # Avoid warnings.
  end

  def version_requirements
    normalize if defined? @version_requirement and @version_requirement
    @version_requirements
  end

  def requirement_list
    version_requirements.as_list
  end

  alias requirements_list requirement_list

  def normalize
    ver = @version_requirement.instance_eval { @version }
    @version_requirements = Gem::Requirement.new([ver])
    @version_requirement = nil
  end

  def to_s # :nodoc:
    "#{name} (#{version_requirements}, #{@type || :runtime})"
  end

  def ==(other) # :nodoc:
    self.class === other &&
      self.name == other.name &&
      self.type == other.type &&
      self.version_requirements == other.version_requirements
  end

  ##
  # Uses this dependency as a pattern to compare to the dependency +other+.
  # This dependency will match if the name matches the other's name, and other
  # has only an equal version requirement that satisfies this dependency.

  def =~(other)
    return false unless self.class === other

    pattern = @name
    pattern = /\A#{@name}\Z/ unless Regexp === pattern

    return false unless pattern =~ other.name

    reqs = other.version_requirements.requirements

    return false unless reqs.length == 1
    return false unless reqs.first.first == '='

    version = reqs.first.last

    version_requirements.satisfied_by? version
  end

  def hash # :nodoc:
    name.hash + type.hash + version_requirements.hash
  end

end

