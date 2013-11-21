##
# A ComposedSet allows multiple sets to be queried like a single set.
#
# To create a composed set with any number of sets use:
#
#   Gem::Resolver.compose_sets set1, set2
#
# This method will eliminate nesting of composed sets.

class Gem::Resolver::ComposedSet < Gem::Resolver::Set

  attr_reader :sets # :nodoc:

  ##
  # Creates a new ComposedSet containing +sets+.  Use
  # Gem::Resolver::compose_sets instead.

  def initialize *sets
    @sets = sets
  end

  ##
  # Finds all specs matching +req+ in all sets.

  def find_all req
    res = []
    @sets.each { |s| res += s.find_all(req) }
    res
  end

  ##
  # Prefetches +reqs+ in all sets.

  def prefetch reqs
    @sets.each { |s| s.prefetch(reqs) }
  end

end

