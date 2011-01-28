######################################################################
# This file is imported from the rubygems project.
# DO NOT make modifications in this repo. They _will_ be reverted!
# File a patch instead and assign it to Ryan Davis or Eric Hodel.
######################################################################

require "rubygems/requirement"

##
# The Dependency class holds a Gem name and a Gem::Requirement.

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
  # Allows you to force this dependency to be a prerelease.

  attr_writer :prerelease

  ##
  # Dependency type.

  attr_reader :type

  ##
  # Constructs a dependency with +name+ and +requirements+. The last
  # argument can optionally be the dependency type, which defaults to
  # <tt>:runtime</tt>.

  def initialize name, *requirements
    type         = Symbol === requirements.last ? requirements.pop : :runtime
    requirements = requirements.first if 1 == requirements.length # unpack

    unless TYPES.include? type
      raise ArgumentError, "Valid types are #{TYPES.inspect}, "
        + "not #{type.inspect}"
    end

    @name        = name
    @requirement = Gem::Requirement.create requirements
    @type        = type
    @prerelease  = false

    # This is for Marshal backwards compatibility. See the comments in
    # +requirement+ for the dirty details.

    @version_requirements = @requirement
  end

  ##
  # A dependency's hash is the XOR of the hashes of +name+, +type+,
  # and +requirement+.

  def hash # :nodoc:
    name.hash ^ type.hash ^ requirement.hash
  end

  def inspect # :nodoc:
    "<%s type=%p name=%p requirements=%p>" %
      [self.class, @type, @name, requirement.to_s]
  end

  ##
  # Does this dependency require a prerelease?

  def prerelease?
    @prerelease || requirement.prerelease?
  end

  def pretty_print q # :nodoc:
    q.group 1, 'Gem::Dependency.new(', ')' do
      q.pp name
      q.text ','
      q.breakable

      q.pp requirement

      q.text ','
      q.breakable

      q.pp type
    end
  end

  ##
  # What does this dependency require?

  def requirement
    return @requirement if defined?(@requirement) and @requirement

    # @version_requirements and @version_requirement are legacy ivar
    # names, and supported here because older gems need to keep
    # working and Dependency doesn't implement marshal_dump and
    # marshal_load. In a happier world, this would be an
    # attr_accessor. The horrifying instance_variable_get you see
    # below is also the legacy of some old restructurings.
    #
    # Note also that because of backwards compatibility (loading new
    # gems in an old RubyGems installation), we can't add explicit
    # marshaling to this class until we want to make a big
    # break. Maybe 2.0.
    #
    # Children, define explicit marshal and unmarshal behavior for
    # public classes. Marshal formats are part of your public API.

    if defined?(@version_requirement) && @version_requirement
      version = @version_requirement.instance_variable_get :@version
      @version_requirement  = nil
      @version_requirements = Gem::Requirement.new version
    end

    @requirement = @version_requirements if defined?(@version_requirements)
  end

  def requirements_list
    requirement.as_list
  end

  def to_s # :nodoc:
    "#{name} (#{requirement}, #{type})"
  end

  def == other # :nodoc:
    Gem::Dependency === other &&
      self.name        == other.name &&
      self.type        == other.type &&
      self.requirement == other.requirement
  end

  ##
  # Dependencies are ordered by name.

  def <=> other
    @name <=> other.name
  end

  ##
  # Uses this dependency as a pattern to compare to +other+. This
  # dependency will match if the name matches the other's name, and
  # other has only an equal version requirement that satisfies this
  # dependency.

  def =~ other
    unless Gem::Dependency === other
      return unless other.respond_to?(:name) && other.respond_to?(:version)
      other = Gem::Dependency.new other.name, other.version
    end

    return false unless name === other.name

    reqs = other.requirement.requirements

    return false unless reqs.length == 1
    return false unless reqs.first.first == '='

    version = reqs.first.last

    requirement.satisfied_by? version
  end

  def match? name, version
    return false unless self.name === name
    return true if requirement.none?

    requirement.satisfied_by? Gem::Version.new(version)
  end

  def matches_spec? spec
    return false unless name === spec.name
    return true  if requirement.none?

    requirement.satisfied_by?(spec.version)
  end

end

