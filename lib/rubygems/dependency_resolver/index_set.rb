##
# The global rubygems pool represented via the traditional
# source index.

class Gem::DependencyResolver::IndexSet

  def initialize
    @f = Gem::SpecFetcher.fetcher

    @all = Hash.new { |h,k| h[k] = [] }

    list, = @f.available_specs :released

    list.each do |uri, specs|
      specs.each do |n|
        @all[n.name] << [uri, n]
      end
    end

    @specs = {}
  end

  ##
  # Return an array of IndexSpecification objects matching
  # DependencyRequest +req+.

  def find_all req
    res = []

    name = req.dependency.name

    @all[name].each do |uri, n|
      if req.dependency.match? n then
        res << Gem::DependencyResolver::IndexSpecification.new(
          self, n.name, n.version, uri, n.platform)
      end
    end

    res
  end

  ##
  # Called from IndexSpecification to get a true Specification
  # object.

  def load_spec name, ver, platform, source
    key = "#{name}-#{ver}-#{platform}"

    @specs.fetch key do
      tuple = Gem::NameTuple.new name, ver, platform

      @specs[key] = source.fetch_spec tuple
    end
  end

  ##
  # No prefetching needed since we load the whole index in
  # initially.

  def prefetch gems
  end

end

