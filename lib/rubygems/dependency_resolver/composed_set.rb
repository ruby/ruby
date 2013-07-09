class Gem::DependencyResolver::ComposedSet

  def initialize *sets
    @sets = sets
  end

  def find_all req
    res = []
    @sets.each { |s| res += s.find_all(req) }
    res
  end

  def prefetch reqs
    @sets.each { |s| s.prefetch(reqs) }
  end

end

