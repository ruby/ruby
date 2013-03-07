require 'tempfile'
require 'rubygems'
require 'rubygems/remote_fetcher'

##
# A fake Gem::RemoteFetcher for use in tests or to avoid real live HTTP
# requests when testing code that uses RubyGems.
#
# Example:
#
#   @fetcher = Gem::FakeFetcher.new
#   @fetcher.data['http://gems.example.com/yaml'] = source_index.to_yaml
#   Gem::RemoteFetcher.fetcher = @fetcher
#
#   # invoke RubyGems code
#
#   paths = @fetcher.paths
#   assert_equal 'http://gems.example.com/yaml', paths.shift
#   assert paths.empty?, paths.join(', ')
#
# See RubyGems' tests for more examples of FakeFetcher.

class Gem::FakeFetcher

  attr_reader :data
  attr_reader :last_request
  attr_reader :api_endpoints
  attr_accessor :paths

  def initialize
    @data = {}
    @paths = []
    @api_endpoints = {}
  end

  def api_endpoint(uri)
    @api_endpoints[uri] || uri
  end

  def find_data(path)
    if URI === path and "URI::#{path.scheme.upcase}" != path.class.name then
      raise ArgumentError,
        "mismatch for scheme #{path.scheme} and class #{path.class}"
    end

    path = path.to_s
    @paths << path
    raise ArgumentError, 'need full URI' unless path =~ %r'^https?://'

    unless @data.key? path then
      raise Gem::RemoteFetcher::FetchError.new("no data for #{path}", path)
    end

    @data[path]
  end

  def fetch_path path, mtime = nil, head = false
    data = find_data(path)

    if data.respond_to?(:call) then
      data.call
    else
      if path.to_s =~ /gz$/ and not data.nil? and not data.empty? then
        data = Gem.gunzip data
      end

      data
    end
  end

  def cache_update_path uri, path = nil, update = true
    if data = fetch_path(uri)
      open(path, 'wb') { |io| io.write data } if path and update
      data
    else
      Gem.read_binary(path) if path
    end
  end

  # Thanks, FakeWeb!
  def open_uri_or_path(path)
    data = find_data(path)
    body, code, msg = data

    response = Net::HTTPResponse.send(:response_class, code.to_s).new("1.0", code.to_s, msg)
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response
  end

  def request(uri, request_class, last_modified = nil)
    data = find_data(uri)
    body, code, msg = data

    @last_request = request_class.new uri.request_uri
    yield @last_request if block_given?

    response = Net::HTTPResponse.send(:response_class, code.to_s).new("1.0", code.to_s, msg)
    response.instance_variable_set(:@body, body)
    response.instance_variable_set(:@read, true)
    response
  end

  def fetch_size(path)
    path = path.to_s
    @paths << path

    raise ArgumentError, 'need full URI' unless path =~ %r'^http://'

    unless @data.key? path then
      raise Gem::RemoteFetcher::FetchError.new("no data for #{path}", path)
    end

    data = @data[path]

    data.respond_to?(:call) ? data.call : data.length
  end

  def download spec, source_uri, install_dir = Gem.dir
    name = File.basename spec.cache_file
    path = if Dir.pwd == install_dir then # see fetch_command
             install_dir
           else
             File.join install_dir, "cache"
           end

    path = File.join path, name

    if source_uri =~ /^http/ then
      File.open(path, "wb") do |f|
        f.write fetch_path(File.join(source_uri, "gems", name))
      end
    else
      FileUtils.cp source_uri, path
    end

    path
  end

  def download_to_cache dependency
    found, _ = Gem::SpecFetcher.fetcher.spec_for_dependency dependency

    return if found.empty?

    spec, source = found.first

    download spec, source.uri.to_s
  end

end

# :stopdoc:
class Gem::RemoteFetcher

  def self.fetcher=(fetcher)
    @fetcher = fetcher
  end

end
# :startdoc:

##
# A StringIO duck-typed class that uses Tempfile instead of String as the
# backing store.
#
# This is available when rubygems/test_utilities is required.
#--
# This class was added to flush out problems in Rubinius' IO implementation.

class TempIO < Tempfile
  def initialize(string = '')
    super "TempIO"
    binmode
    write string
    rewind
  end

  def string
    flush
    Gem.read_binary path
  end
end

