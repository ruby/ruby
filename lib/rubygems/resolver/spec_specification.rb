##
# The Resolver::SpecSpecification contains common functionality for
# Resolver specifications that are backed by a Gem::Specification.

class Gem::Resolver::SpecSpecification < Gem::Resolver::Specification

  attr_reader :spec # :nodoc:

  ##
  # A SpecSpecification is created for a +set+ for a Gem::Specification in
  # +spec+.  The +source+ is either where the +spec+ came from, or should be
  # loaded from.

  def initialize set, spec, source = nil
    @set    = set
    @source = source
    @spec   = spec
  end

  ##
  # The dependencies of the gem for this specification

  def dependencies
    spec.dependencies
  end

  ##
  # The name and version of the specification.
  #
  # Unlike Gem::Specification#full_name, the platform is not included.

  def full_name
    "#{spec.name}-#{spec.version}"
  end

  ##
  # The name of the gem for this specification

  def name
    spec.name
  end

  ##
  # The platform this gem works on.

  def platform
    spec.platform
  end

  ##
  # The version of the gem for this specification.

  def version
    spec.version
  end

end

