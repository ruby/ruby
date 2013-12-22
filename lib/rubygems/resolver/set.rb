##
# Resolver sets are used to look up specifications (and their
# dependencies) used in resolution.  This set is abstract.

class Gem::Resolver::Set

  ##
  # The find_all method must be implemented.  It returns all Resolver
  # Specification objects matching the given DependencyRequest +req+.

  def find_all req
    raise NotImplementedError
  end

  ##
  # The #prefetch method may be overridden, but this is not necessary.  This
  # default implementation does nothing, which is suitable for sets where
  # looking up a specification is cheap (such as installed gems).
  #
  # When overridden, the #prefetch method should look up specifications
  # matching +reqs+.

  def prefetch reqs
  end

end

