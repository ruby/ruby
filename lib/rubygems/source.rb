# frozen_string_literal: true
require 'uri'
require 'fileutils'

##
# A Source knows how to list and fetch gems from a RubyGems marshal index.
#
# There are other Source subclasses for installed gems, local gems, the
# bundler dependency API and so-forth.

class Gem::Source

  include Comparable

  FILES = { # :nodoc:
    :released   => 'specs',
    :latest     => 'latest_specs',
    :prerelease => 'prerelease_specs',
  }

  ##
  # The URI this source will fetch gems from.

  attr_reader :uri

  ##
  # Creates a new Source which will use the index located at +uri+.

  def initialize(uri)
    begin
      unless uri.kind_of? URI
        uri = URI.parse(uri.to_s)
      end
    rescue URI::InvalidURIError
      raise if Gem::Source == self.class
    end

    @uri = uri
    @api_uri = nil
  end

  ##
  # Use an SRV record on the host to look up the true endpoint for the index.

  def api_uri # :nodoc:
    require 'rubygems/remote_fetcher'
    @api_uri ||= Gem::RemoteFetcher.fetcher.api_endpoint uri
  end

  ##
  # Sources are ordered by installation preference.

  def <=>(other)
    case other
    when Gem::Source::Installed,
         Gem::Source::Local,
         Gem::Source::Lock,
         Gem::Source::SpecificFile,
         Gem::Source::Git,
         Gem::Source::Vendor then
      -1
    when Gem::Source then
      if !@uri
        return 0 unless other.uri
        return 1
      end

      return -1 if !other.uri

      @uri.to_s <=> other.uri.to_s
    else
      nil
    end
  end

  def == other # :nodoc:
    self.class === other and @uri == other.uri
  end

  alias_method :eql?, :== # :nodoc:

  ##
  # Returns a Set that can fetch specifications from this source.

  def dependency_resolver_set # :nodoc:
    return Gem::Resolver::IndexSet.new self if 'file' == api_uri.scheme

    bundler_api_uri = api_uri + './api/v1/dependencies'

    begin
      fetcher = Gem::RemoteFetcher.fetcher
      response = fetcher.fetch_path bundler_api_uri, nil, true
    rescue Gem::RemoteFetcher::FetchError
      Gem::Resolver::IndexSet.new self
    else
      if response.respond_to? :uri then
        Gem::Resolver::APISet.new response.uri
      else
        Gem::Resolver::APISet.new bundler_api_uri
      end
    end
  end

  def hash # :nodoc:
    @uri.hash
  end

  ##
  # Returns the local directory to write +uri+ to.

  def cache_dir(uri)
    # Correct for windows paths
    escaped_path = uri.path.sub(/^\/([a-z]):\//i, '/\\1-/')
    escaped_path.untaint

    File.join Gem.spec_cache_dir, "#{uri.host}%#{uri.port}", File.dirname(escaped_path)
  end

  ##
  # Returns true when it is possible and safe to update the cache directory.

  def update_cache?
    @update_cache ||=
      begin
        File.stat(Gem.user_home).uid == Process.uid
      rescue Errno::ENOENT
        false
      end
  end

  ##
  # Fetches a specification for the given +name_tuple+.

  def fetch_spec name_tuple
    fetcher = Gem::RemoteFetcher.fetcher

    spec_file_name = name_tuple.spec_name

    uri = api_uri + "#{Gem::MARSHAL_SPEC_DIR}#{spec_file_name}"

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
    spec_path  = api_uri + "#{file_name}.gz"
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

  ##
  # Downloads +spec+ and writes it to +dir+.  See also
  # Gem::RemoteFetcher#download.

  def download(spec, dir=Dir.pwd)
    fetcher = Gem::RemoteFetcher.fetcher
    fetcher.download spec, api_uri.to_s, dir
  end

  def pretty_print q # :nodoc:
    q.group 2, '[Remote:', ']' do
      q.breakable
      q.text @uri.to_s

      if api = api_uri
        q.breakable
        q.text 'API URI: '
        q.text api.to_s
      end
    end
  end

end

require 'rubygems/source/git'
require 'rubygems/source/installed'
require 'rubygems/source/specific_file'
require 'rubygems/source/local'
require 'rubygems/source/lock'
require 'rubygems/source/vendor'

