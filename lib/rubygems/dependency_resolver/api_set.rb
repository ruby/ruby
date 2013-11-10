##
# The global rubygems pool, available via the rubygems.org API.
# Returns instances of APISpecification.

class Gem::DependencyResolver::APISet < Gem::DependencyResolver::Set

  ##
  # The URI for the dependency API this APISet uses.

  attr_reader :dep_uri # :nodoc:

  ##
  # Creates a new APISet that will retrieve gems from +uri+ using the RubyGems
  # API described at http://guides.rubygems.org/rubygems-org-api

  def initialize uri = 'https://rubygems.org/api/v1/dependencies'
    uri = URI uri unless URI === uri # for ruby 1.8
    @data = Hash.new { |h,k| h[k] = [] }
    @dep_uri = uri
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

  def versions name # :nodoc:
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

