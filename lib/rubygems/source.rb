require 'uri'
require 'fileutils'

class Gem::Source
  FILES = {
    :released   => 'specs',
    :latest     => 'latest_specs',
    :prerelease => 'prerelease_specs',
  }

  def initialize(uri)
    unless uri.kind_of? URI
      uri = URI.parse(uri.to_s)
    end

    @uri = uri
    @api_uri = nil
  end

  attr_reader :uri

  def api_uri
    require 'rubygems/remote_fetcher'
    @api_uri ||= Gem::RemoteFetcher.fetcher.api_endpoint uri
  end

  def <=>(other)
    if !@uri
      return 0 unless other.uri
      return -1
    end

    return 1 if !other.uri

    @uri.to_s <=> other.uri.to_s
  end

  include Comparable

  def ==(other)
    case other
    when self.class
      @uri == other.uri
    else
      false
    end
  end

  alias_method :eql?, :==

  def hash
    @uri.hash
  end

  ##
  # Returns the local directory to write +uri+ to.

  def cache_dir(uri)
    # Correct for windows paths
    escaped_path = uri.path.sub(/^\/([a-z]):\//i, '/\\1-/')
    root = File.join Gem.user_home, '.gem', 'specs'
    File.join root, "#{uri.host}%#{uri.port}", File.dirname(escaped_path)
  end

  def update_cache?
    @update_cache ||=
      begin
        File.stat(Gem.user_home).uid == Process.uid
      rescue Errno::ENOENT
        false
      end
  end

  def fetch_spec(name)
    fetcher = Gem::RemoteFetcher.fetcher

    spec_file_name = name.spec_name

    uri = @uri + "#{Gem::MARSHAL_SPEC_DIR}#{spec_file_name}"

    cache_dir = cache_dir uri

    local_spec = File.join cache_dir, spec_file_name

    if File.exist? local_spec then
      spec = Gem.read_binary local_spec
      spec = Marshal.load(spec) rescue nil
      return spec if spec
    end

    uri.path << '.rz'

    spec = fetcher.fetch_path uri
    spec = Gem.inflate spec

    if update_cache? then
      FileUtils.mkdir_p cache_dir

      open local_spec, 'wb' do |io|
        io.write spec
      end
    end

    # TODO: Investigate setting Gem::Specification#loaded_from to a URI
    Marshal.load spec
  end

  ##
  # Loads +type+ kind of specs fetching from +@uri+ if the on-disk cache is
  # out of date.
  #
  # +type+ is one of the following:
  #
  # :released   => Return the list of all released specs
  # :latest     => Return the list of only the highest version of each gem
  # :prerelease => Return the list of all prerelease only specs
  #

  def load_specs(type)
    file       = FILES[type]
    fetcher    = Gem::RemoteFetcher.fetcher
    file_name  = "#{file}.#{Gem.marshal_version}"
    spec_path  = @uri + "#{file_name}.gz"
    cache_dir  = cache_dir spec_path
    local_file = File.join(cache_dir, file_name)
    retried    = false

    FileUtils.mkdir_p cache_dir if update_cache?

    spec_dump = fetcher.cache_update_path spec_path, local_file, update_cache?

    begin
      Gem::NameTuple.from_list Marshal.load(spec_dump)
    rescue ArgumentError
      if update_cache? && !retried
        FileUtils.rm local_file
        retried = true
        retry
      else
        raise Gem::Exception.new("Invalid spec cache file in #{local_file}")
      end
    end
  end

  def download(spec, dir=Dir.pwd)
    fetcher = Gem::RemoteFetcher.fetcher
    fetcher.download spec, @uri.to_s, dir
  end
end
