##
# The global rubygems pool represented via the traditional
# source index.

class Gem::DependencyResolver::IndexSet < Gem::DependencyResolver::Set

  def initialize source = nil # :nodoc:
    @f =
      if source then
        sources = Gem::SourceList.from [source]

        Gem::SpecFetcher.new sources
      else
        Gem::SpecFetcher.fetcher
      end

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

end

