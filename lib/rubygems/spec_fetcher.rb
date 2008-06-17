require 'zlib'

require 'rubygems'
require 'rubygems/remote_fetcher'
require 'rubygems/user_interaction'

##
# SpecFetcher handles metadata updates from remote gem repositories.

class Gem::SpecFetcher

  include Gem::UserInteraction

  ##
  # The SpecFetcher cache dir.

  attr_reader :dir # :nodoc:

  ##
  # Cache of latest specs

  attr_reader :latest_specs # :nodoc:

  ##
  # Cache of all spces

  attr_reader :specs # :nodoc:

  @fetcher = nil

  def self.fetcher
    @fetcher ||= new
  end

  def self.fetcher=(fetcher) # :nodoc:
    @fetcher = fetcher
  end

  def initialize
    @dir = File.join Gem.user_home, '.gem', 'specs'
    @update_cache = File.stat(Gem.user_home).uid == Process.uid

    @specs = {}
    @latest_specs = {}

    @fetcher = Gem::RemoteFetcher.fetcher
  end

  ##
  # Retuns the local directory to write +uri+ to.

  def cache_dir(uri)
    File.join @dir, "#{uri.host}%#{uri.port}", File.dirname(uri.path)
  end

  ##
  # Fetch specs matching +dependency+.  If +all+ is true, all matching
  # versions are returned.  If +matching_platform+ is false, all platforms are
  # returned.

  def fetch(dependency, all = false, matching_platform = true)
    specs_and_sources = find_matching dependency, all, matching_platform

    specs_and_sources.map do |spec_tuple, source_uri|
      [fetch_spec(spec_tuple, URI.parse(source_uri)), source_uri]
    end

  rescue Gem::RemoteFetcher::FetchError => e
    raise unless warn_legacy e do
      require 'rubygems/source_info_cache'

      return Gem::SourceInfoCache.search_with_source(dependency,
                                                     matching_platform, all)
    end
  end

  def fetch_spec(spec, source_uri)
    spec = spec - [nil, 'ruby', '']
    spec_file_name = "#{spec.join '-'}.gemspec"

    uri = source_uri + "#{Gem::MARSHAL_SPEC_DIR}#{spec_file_name}"

    cache_dir = cache_dir uri

    local_spec = File.join cache_dir, spec_file_name

    if File.exist? local_spec then
      spec = Gem.read_binary local_spec
    else
      uri.path << '.rz'

      spec = @fetcher.fetch_path uri
      spec = Gem.inflate spec

      if @update_cache then
        FileUtils.mkdir_p cache_dir

        open local_spec, 'wb' do |io|
          io.write spec
        end
      end
    end

    # TODO: Investigate setting Gem::Specification#loaded_from to a URI
    Marshal.load spec
  end

  ##
  # Find spec names that match +dependency+.  If +all+ is true, all matching
  # versions are returned.  If +matching_platform+ is false, gems for all
  # platforms are returned.

  def find_matching(dependency, all = false, matching_platform = true)
    found = {}

    list(all).each do |source_uri, specs|
      found[source_uri] = specs.select do |spec_name, version, spec_platform|
        dependency =~ Gem::Dependency.new(spec_name, version) and
          (not matching_platform or Gem::Platform.match(spec_platform))
      end
    end

    specs_and_sources = []

    found.each do |source_uri, specs|
      uri_str = source_uri.to_s
      specs_and_sources.push(*specs.map { |spec| [spec, uri_str] })
    end

    specs_and_sources
  end

  ##
  # Returns Array of gem repositories that were generated with RubyGems less
  # than 1.2.

  def legacy_repos
    Gem.sources.reject do |source_uri|
      source_uri = URI.parse source_uri
      spec_path = source_uri + "specs.#{Gem.marshal_version}.gz"

      begin
        @fetcher.fetch_size spec_path
      rescue Gem::RemoteFetcher::FetchError
        begin
          @fetcher.fetch_size(source_uri + 'yaml') # re-raise if non-repo
        rescue Gem::RemoteFetcher::FetchError
          alert_error "#{source_uri} does not appear to be a repository"
          raise
        end
        false
      end
    end
  end

  ##
  # Returns a list of gems available for each source in Gem::sources.  If
  # +all+ is true, all versions are returned instead of only latest versions.

  def list(all = false)
    list = {}

    file = all ? 'specs' : 'latest_specs'

    Gem.sources.each do |source_uri|
      source_uri = URI.parse source_uri

      if all and @specs.include? source_uri then
        list[source_uri] = @specs[source_uri]
      elsif @latest_specs.include? source_uri then
        list[source_uri] = @latest_specs[source_uri]
      else
        specs = load_specs source_uri, file

        cache = all ? @specs : @latest_specs

        cache[source_uri] = specs
        list[source_uri] = specs
      end
    end

    list
  end

  def load_specs(source_uri, file)
    file_name = "#{file}.#{Gem.marshal_version}.gz"

    spec_path = source_uri + file_name

    cache_dir = cache_dir spec_path

    local_file = File.join(cache_dir, file_name).chomp '.gz'

    if File.exist? local_file then
      local_size = File.stat(local_file).size

      remote_file = spec_path.dup
      remote_file.path = remote_file.path.chomp '.gz'
      remote_size = @fetcher.fetch_size remote_file

      spec_dump = Gem.read_binary local_file if remote_size == local_size
    end

    unless spec_dump then
      loaded = true

      spec_dump_gz = @fetcher.fetch_path spec_path
      spec_dump = Gem.gunzip spec_dump_gz
    end

    specs = Marshal.load spec_dump

    if loaded and @update_cache then
      begin
        FileUtils.mkdir_p cache_dir

        open local_file, 'wb' do |io|
          Marshal.dump specs, io
        end
      rescue
      end
    end

    specs
  end

  ##
  # Warn about legacy repositories if +exception+ indicates only legacy
  # repositories are available, and yield to the block.  Returns false if the
  # exception indicates some other FetchError.

  def warn_legacy(exception)
    uri = exception.uri.to_s
    if uri =~ /specs\.#{Regexp.escape Gem.marshal_version}\.gz$/ then
      alert_warning <<-EOF
RubyGems 1.2+ index not found for:
\t#{legacy_repos.join "\n\t"}

RubyGems will revert to legacy indexes degrading performance.
      EOF

      yield

      return true
    end

    false
  end

end

