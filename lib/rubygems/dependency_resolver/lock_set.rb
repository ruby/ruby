##
# A set of gems from a gem dependencies lockfile.

class Gem::DependencyResolver::LockSet < Gem::DependencyResolver::Set

  attr_reader :specs # :nodoc:

  ##
  # Creates a new LockSet from the given +source+

  def initialize source
    @source = source
    @specs  = []
  end

  ##
  # Creates a new IndexSpecification in this set using the given +name+,
  # +version+ and +platform+.
  #
  # The specification's set will be the current set, and the source will be
  # the current set's source.

  def add name, version, platform # :nodoc:
    version = Gem::Version.new version

    spec =
      Gem::DependencyResolver::IndexSpecification.new self, name, version,
                                                      @source, platform

    @specs << spec
  end

  ##
  # Returns an Array of IndexSpecification objects matching the
  # DependencyRequest +req+.

  def find_all req
    @specs.select do |spec|
      req.matches_spec? spec
    end
  end

  ##
  # Loads a Gem::Specification with the given +name+, +version+ and
  # +platform+.  +source+ is ignored.

  def load_spec name, version, platform, source # :nodoc:
    dep = Gem::Dependency.new name, version

    found = @specs.find do |spec|
      dep.matches_spec? spec and spec.platform == platform
    end

    tuple = Gem::NameTuple.new found.name, found.version, found.platform

    found.source.fetch_spec tuple
  end

end

