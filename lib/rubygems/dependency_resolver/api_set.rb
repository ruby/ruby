##
# The global rubygems pool, available via the rubygems.org API.
# Returns instances of APISpecification.

class Gem::DependencyResolver::APISet

  def initialize
    @data = Hash.new { |h,k| h[k] = [] }
    @dep_uri = URI 'https://rubygems.org/api/v1/dependencies'
  end

  ##
  # Return an array of APISpecification objects matching
  # DependencyRequest +req+.

  def find_all req
    res = []

    versions(req.name).each do |ver|
      if req.dependency.match? req.name, ver[:number]
        res << Gem::DependencyResolver::APISpecification.new(self, ver)
      end
    end

    res
  end

  ##
  # A hint run by the resolver to allow the Set to fetch
  # data for DependencyRequests +reqs+.

  def prefetch reqs
    names = reqs.map { |r| r.dependency.name }
    needed = names.find_all { |d| !@data.key?(d) }

    return if needed.empty?

    uri = @dep_uri + "?gems=#{needed.sort.join ','}"
    str = Gem::RemoteFetcher.fetcher.fetch_path uri

    Marshal.load(str).each do |ver|
      @data[ver[:name]] << ver
    end
  end

  ##
  # Return data for all versions of the gem +name+.

  def versions name
    if @data.key?(name)
      return @data[name]
    end

    uri = @dep_uri + "?gems=#{name}"
    str = Gem::RemoteFetcher.fetcher.fetch_path uri

    Marshal.load(str).each do |ver|
      @data[ver[:name]] << ver
    end

    @data[name]
  end

end

