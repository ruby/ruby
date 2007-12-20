require 'net/http'
require 'uri'

require 'rubygems'
require 'rubygems/gem_open_uri'

##
# RemoteFetcher handles the details of fetching gems and gem information from
# a remote source.

class Gem::RemoteFetcher

  class FetchError < Gem::Exception; end

  @fetcher = nil

  # Cached RemoteFetcher instance.
  def self.fetcher
    @fetcher ||= self.new Gem.configuration[:http_proxy]
  end

  # Initialize a remote fetcher using the source URI and possible proxy
  # information.
  #
  # +proxy+
  # * [String]: explicit specification of proxy; overrides any environment
  #             variable setting
  # * nil: respect environment variables (HTTP_PROXY, HTTP_PROXY_USER,
  #        HTTP_PROXY_PASS)
  # * <tt>:no_proxy</tt>: ignore environment variables and _don't_ use a proxy
  def initialize(proxy)
    @proxy_uri =
      case proxy
      when :no_proxy then nil
      when nil then get_proxy_from_env
      when URI::HTTP then proxy
      else URI.parse(proxy)
      end
  end

  # Downloads +uri+.
  def fetch_path(uri)
    open_uri_or_path(uri) do |input|
      input.read
    end
  rescue Timeout::Error
    raise FetchError, "timed out fetching #{uri}"
  rescue IOError, SocketError, SystemCallError => e
    raise FetchError, "#{e.class}: #{e} reading #{uri}"
  rescue OpenURI::HTTPError => e
    body = e.io.readlines.join "\n\t"
    message = "#{e.class}: #{e} reading #{uri}\n\t#{body}"
    raise FetchError, message
  end

  # Returns the size of +uri+ in bytes.
  def fetch_size(uri)
    return File.size(get_file_uri_path(uri)) if file_uri? uri

    uri = URI.parse uri unless URI::Generic === uri

    raise ArgumentError, 'uri is not an HTTP URI' unless URI::HTTP === uri

    http = connect_to uri.host, uri.port

    request = Net::HTTP::Head.new uri.request_uri

    request.basic_auth unescape(uri.user), unescape(uri.password) unless
      uri.user.nil? or uri.user.empty?

    resp = http.request request

    if resp.code !~ /^2/ then
      raise Gem::RemoteSourceException,
            "HTTP Response #{resp.code} fetching #{uri}"
    end

    if resp['content-length'] then
      return resp['content-length'].to_i
    else
      resp = http.get uri.request_uri
      return resp.body.size
    end

  rescue SocketError, SystemCallError, Timeout::Error => e
    raise FetchError, "#{e.message} (#{e.class})\n\tgetting size of #{uri}"
  end

  private

  def escape(str)
    return unless str
    URI.escape(str)
  end

  def unescape(str)
    return unless str
    URI.unescape(str)
  end

  # Returns an HTTP proxy URI if one is set in the environment variables.
  def get_proxy_from_env
    env_proxy = ENV['http_proxy'] || ENV['HTTP_PROXY']

    return nil if env_proxy.nil? or env_proxy.empty?

    uri = URI.parse env_proxy

    if uri and uri.user.nil? and uri.password.nil? then
      # Probably we have http_proxy_* variables?
      uri.user = escape(ENV['http_proxy_user'] || ENV['HTTP_PROXY_USER'])
      uri.password = escape(ENV['http_proxy_pass'] || ENV['HTTP_PROXY_PASS'])
    end

    uri
  end

  # Normalize the URI by adding "http://" if it is missing.
  def normalize_uri(uri)
    (uri =~ /^(https?|ftp|file):/) ? uri : "http://#{uri}"
  end

  # Connect to the source host/port, using a proxy if needed.
  def connect_to(host, port)
    if @proxy_uri
      Net::HTTP::Proxy(@proxy_uri.host, @proxy_uri.port, unescape(@proxy_uri.user), unescape(@proxy_uri.password)).new(host, port)
    else
      Net::HTTP.new(host, port)
    end
  end

  # Read the data from the (source based) URI, but if it is a file:// URI,
  # read from the filesystem instead.
  def open_uri_or_path(uri, &block)
    if file_uri?(uri)
      open(get_file_uri_path(uri), &block)
    else
      connection_options = {
        "User-Agent" => "RubyGems/#{Gem::RubyGemsVersion} #{Gem::Platform.local}"
      }

      if @proxy_uri
        http_proxy_url = "#{@proxy_uri.scheme}://#{@proxy_uri.host}:#{@proxy_uri.port}"  
        connection_options[:proxy_http_basic_authentication] = [http_proxy_url, unescape(@proxy_uri.user)||'', unescape(@proxy_uri.password)||'']
      end

      uri = URI.parse uri unless URI::Generic === uri
      unless uri.nil? || uri.user.nil? || uri.user.empty? then
        connection_options[:http_basic_authentication] =
          [unescape(uri.user), unescape(uri.password)]
      end

      open(uri, connection_options, &block)
    end
  end

  # Checks if the provided string is a file:// URI.
  def file_uri?(uri)
    uri =~ %r{\Afile://}
  end

  # Given a file:// URI, returns its local path.
  def get_file_uri_path(uri)
    uri.sub(%r{\Afile://}, '')
  end

end

