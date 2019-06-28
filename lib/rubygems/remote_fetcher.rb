# frozen_string_literal: true
require 'rubygems'
require 'rubygems/request'
require 'rubygems/uri_formatter'
require 'rubygems/user_interaction'
require 'rubygems/request/connection_pools'
require 'resolv'

##
# RemoteFetcher handles the details of fetching gems and gem information from
# a remote source.

class Gem::RemoteFetcher

  include Gem::UserInteraction

  ##
  # A FetchError exception wraps up the various possible IO and HTTP failures
  # that could happen while downloading from the internet.

  class FetchError < Gem::Exception

    ##
    # The URI which was being accessed when the exception happened.

    attr_accessor :uri

    def initialize(message, uri)
      super message
      begin
        uri = URI(uri)
        uri.password = 'REDACTED' if uri.password
        @uri = uri.to_s
      rescue URI::InvalidURIError, ArgumentError
        @uri = uri
      end
    end

    def to_s # :nodoc:
      "#{super} (#{uri})"
    end

  end

  ##
  # A FetchError that indicates that the reason for not being
  # able to fetch data was that the host could not be contacted

  class UnknownHostError < FetchError
  end

  @fetcher = nil

  ##
  # Cached RemoteFetcher instance.

  def self.fetcher
    @fetcher ||= self.new Gem.configuration[:http_proxy]
  end

  attr_accessor :headers

  ##
  # Initialize a remote fetcher using the source URI and possible proxy
  # information.
  #
  # +proxy+
  # * [String]: explicit specification of proxy; overrides any environment
  #             variable setting
  # * nil: respect environment variables (HTTP_PROXY, HTTP_PROXY_USER,
  #        HTTP_PROXY_PASS)
  # * <tt>:no_proxy</tt>: ignore environment variables and _don't_ use a proxy
  #
  # +headers+: A set of additional HTTP headers to be sent to the server when
  #            fetching the gem.

  def initialize(proxy=nil, dns=nil, headers={})
    require 'net/http'
    require 'stringio'
    require 'time'
    require 'uri'

    Socket.do_not_reverse_lookup = true

    @proxy = proxy
    @pools = {}
    @pool_lock = Mutex.new
    @cert_files = Gem::Request.get_cert_files

    @headers = headers
  end

  ##
  # Given a name and requirement, downloads this gem into cache and returns the
  # filename. Returns nil if the gem cannot be located.
  #--
  # Should probably be integrated with #download below, but that will be a
  # larger, more encompassing effort. -erikh

  def download_to_cache(dependency)
    found, _ = Gem::SpecFetcher.fetcher.spec_for_dependency dependency

    return if found.empty?

    spec, source = found.max_by { |(s,_)| s.version }

    download spec, source.uri.to_s
  end

  ##
  # Moves the gem +spec+ from +source_uri+ to the cache dir unless it is
  # already there.  If the source_uri is local the gem cache dir copy is
  # always replaced.

  def download(spec, source_uri, install_dir = Gem.dir)
    cache_dir =
      if Dir.pwd == install_dir  # see fetch_command
        install_dir
      elsif File.writable? install_dir
        File.join install_dir, "cache"
      else
        File.join Gem.user_dir, "cache"
      end

    gem_file_name = File.basename spec.cache_file
    local_gem_path = File.join cache_dir, gem_file_name

    FileUtils.mkdir_p cache_dir rescue nil unless File.exist? cache_dir

    # Always escape URI's to deal with potential spaces and such
    # It should also be considered that source_uri may already be
    # a valid URI with escaped characters. e.g. "{DESede}" is encoded
    # as "%7BDESede%7D". If this is escaped again the percentage
    # symbols will be escaped.
    unless source_uri.is_a?(URI::Generic)
      begin
        source_uri = URI.parse(source_uri)
      rescue
        source_uri = URI.parse(URI::DEFAULT_PARSER.escape(source_uri.to_s))
      end
    end

    scheme = source_uri.scheme

    # URI.parse gets confused by MS Windows paths with forward slashes.
    scheme = nil if scheme =~ /^[a-z]$/i

    # REFACTOR: split this up and dispatch on scheme (eg download_http)
    # REFACTOR: be sure to clean up fake fetcher when you do this... cleaner
    case scheme
    when 'http', 'https', 's3' then
      unless File.exist? local_gem_path
        begin
          verbose "Downloading gem #{gem_file_name}"

          remote_gem_path = source_uri + "gems/#{gem_file_name}"

          self.cache_update_path remote_gem_path, local_gem_path
        rescue Gem::RemoteFetcher::FetchError
          raise if spec.original_platform == spec.platform

          alternate_name = "#{spec.original_name}.gem"

          verbose "Failed, downloading gem #{alternate_name}"

          remote_gem_path = source_uri + "gems/#{alternate_name}"

          self.cache_update_path remote_gem_path, local_gem_path
        end
      end
    when 'file' then
      begin
        path = source_uri.path
        path = File.dirname(path) if File.extname(path) == '.gem'

        remote_gem_path = Gem::Util.correct_for_windows_path(File.join(path, 'gems', gem_file_name))

        FileUtils.cp(remote_gem_path, local_gem_path)
      rescue Errno::EACCES
        local_gem_path = source_uri.to_s
      end

      verbose "Using local gem #{local_gem_path}"
    when nil then # TODO test for local overriding cache
      source_path = if Gem.win_platform? && source_uri.scheme &&
                       !source_uri.path.include?(':')
                      "#{source_uri.scheme}:#{source_uri.path}"
                    else
                      source_uri.path
                    end

      source_path = Gem::UriFormatter.new(source_path).unescape

      begin
        FileUtils.cp source_path, local_gem_path unless
          File.identical?(source_path, local_gem_path)
      rescue Errno::EACCES
        local_gem_path = source_uri.to_s
      end

      verbose "Using local gem #{local_gem_path}"
    else
      raise ArgumentError, "unsupported URI scheme #{source_uri.scheme}"
    end

    local_gem_path
  end

  ##
  # File Fetcher. Dispatched by +fetch_path+. Use it instead.

  def fetch_file(uri, *_)
    Gem.read_binary Gem::Util.correct_for_windows_path uri.path
  end

  ##
  # HTTP Fetcher. Dispatched by +fetch_path+. Use it instead.

  def fetch_http(uri, last_modified = nil, head = false, depth = 0)
    fetch_type = head ? Net::HTTP::Head : Net::HTTP::Get
    response   = request uri, fetch_type, last_modified do |req|
      headers.each { |k,v| req.add_field(k,v) }
    end

    case response
    when Net::HTTPOK, Net::HTTPNotModified then
      response.uri = uri if response.respond_to? :uri
      head ? response : response.body
    when Net::HTTPMovedPermanently, Net::HTTPFound, Net::HTTPSeeOther,
         Net::HTTPTemporaryRedirect then
      raise FetchError.new('too many redirects', uri) if depth > 10

      unless location = response['Location']
        raise FetchError.new("redirecting but no redirect location was given", uri)
      end
      location = URI.parse response['Location']

      if https?(uri) && !https?(location)
        raise FetchError.new("redirecting to non-https resource: #{location}", uri)
      end

      fetch_http(location, last_modified, head, depth + 1)
    else
      raise FetchError.new("bad response #{response.message} #{response.code}", uri)
    end
  end

  alias :fetch_https :fetch_http

  ##
  # Downloads +uri+ and returns it as a String.

  def fetch_path(uri, mtime = nil, head = false)
    uri = URI.parse uri unless URI::Generic === uri

    raise ArgumentError, "bad uri: #{uri}" unless uri

    unless uri.scheme
      raise ArgumentError, "uri scheme is invalid: #{uri.scheme.inspect}"
    end

    data = send "fetch_#{uri.scheme}", uri, mtime, head

    if data and !head and uri.to_s =~ /\.gz$/
      begin
        data = Gem::Util.gunzip data
      rescue Zlib::GzipFile::Error
        raise FetchError.new("server did not return a valid file", uri.to_s)
      end
    end

    data
  rescue FetchError
    raise
  rescue Timeout::Error
    raise UnknownHostError.new('timed out', uri.to_s)
  rescue IOError, SocketError, SystemCallError,
    *(OpenSSL::SSL::SSLError if defined?(OpenSSL)) => e
    if e.message =~ /getaddrinfo/
      raise UnknownHostError.new('no such name', uri.to_s)
    else
      raise FetchError.new("#{e.class}: #{e}", uri.to_s)
    end
  end

  def fetch_s3(uri, mtime = nil, head = false)
    public_uri = sign_s3_url(uri)
    fetch_https public_uri, mtime, head
  end

  ##
  # Downloads +uri+ to +path+ if necessary. If no path is given, it just
  # passes the data.

  def cache_update_path(uri, path = nil, update = true)
    mtime = path && File.stat(path).mtime rescue nil

    data = fetch_path(uri, mtime)

    if data == nil # indicates the server returned 304 Not Modified
      return Gem.read_binary(path)
    end

    if update and path
      Gem.write_binary(path, data)
    end

    data
  end

  ##
  # Returns the size of +uri+ in bytes.

  def fetch_size(uri) # TODO: phase this out
    response = fetch_path(uri, nil, true)

    response['content-length'].to_i
  end

  ##
  # Performs a Net::HTTP request of type +request_class+ on +uri+ returning
  # a Net::HTTP response object.  request maintains a table of persistent
  # connections to reduce connect overhead.

  def request(uri, request_class, last_modified = nil)
    proxy = proxy_for @proxy, uri
    pool  = pools_for(proxy).pool_for uri

    request = Gem::Request.new uri, request_class, last_modified, pool

    request.fetch do |req|
      yield req if block_given?
    end
  end

  def https?(uri)
    uri.scheme.downcase == 'https'
  end

  def close_all
    @pools.each_value {|pool| pool.close_all}
  end

  protected

  S3Config = Struct.new :access_key_id, :secret_access_key, :security_token, :region

  # we have our own signing code here to avoid a dependency on the aws-sdk gem
  def sign_s3_url(uri, expiration = nil)
    require 'base64'
    require 'digest'
    require 'openssl'

    s3_config = s3_source_auth uri
    expiration ||= 86400

    current_time = Time.now.utc
    date_time = current_time.strftime("%Y%m%dT%H%m%SZ")
    date = date_time[0,8]

    credential_info = "#{date}/#{s3_config.region}/s3/aws4_request"
    canonical_host = "#{uri.host}.s3.#{s3_config.region}.amazonaws.com"

    canonical_params = {}
    canonical_params['X-Amz-Algorithm'] = "AWS4-HMAC-SHA256"
    canonical_params['X-Amz-Credential'] = "#{s3_config.access_key_id}/#{credential_info}"
    canonical_params['X-Amz-Date'] = date_time
    canonical_params['X-Amz-Expires'] = expiration.to_s
    canonical_params['X-Amz-SignedHeaders'] = "host"
    canonical_params['X-Amz-Security-Token'] = s3_config.security_token if s3_config.security_token

    # Sorting is required to generate proper signature
    query_params = canonical_params.sort.to_h.map do |key, value|
      "#{base64_uri_escape(key)}=#{base64_uri_escape(value)}"
    end.join('&')

    canonical_request = [
      'GET',
      uri.path,
      query_params,
      "host:#{canonical_host}",
      '', # empty params
      'host',
      'UNSIGNED-PAYLOAD',
    ].join("\n")

    string_to_sign = [
      "AWS4-HMAC-SHA256",
      date_time,
      credential_info,
      Digest::SHA256.hexdigest(canonical_request)
    ].join("\n")

    date_key = OpenSSL::HMAC.digest('sha256', "AWS4" + s3_config.secret_access_key, date)
    date_region_key = OpenSSL::HMAC.digest('sha256', date_key, s3_config.region)
    date_region_service_key = OpenSSL::HMAC.digest('sha256', date_region_key, "s3")
    signing_key = OpenSSL::HMAC.digest('sha256', date_region_service_key, "aws4_request")
    signature = OpenSSL::HMAC.hexdigest('sha256', signing_key, string_to_sign)

    URI.parse("https://#{canonical_host}#{uri.path}?#{query_params}&X-Amz-Signature=#{signature}")
  end

  BASE64_URI_TRANSLATE = { '+' => '%2B', '/' => '%2F', '=' => '%3D' }.freeze

  private

  def base64_uri_escape(str)
    str.gsub("\n", '').gsub(/[\+\/=]/) { |c| BASE64_URI_TRANSLATE[c] }
  end

  def proxy_for(proxy, uri)
    Gem::Request.proxy_uri(proxy || Gem::Request.get_proxy_from_env(uri.scheme))
  end

  def pools_for(proxy)
    @pool_lock.synchronize do
      @pools[proxy] ||= Gem::Request::ConnectionPools.new proxy, @cert_files
    end
  end

  def s3_source_auth(uri)
    return S3Config.new(uri.user, uri.password, nil, 'us-east-1') if uri.user && uri.password

    s3_source = Gem.configuration[:s3_source] || Gem.configuration['s3_source']
    host = uri.host
    raise FetchError.new("no s3_source key exists in .gemrc", "s3://#{host}") unless s3_source

    auth = s3_source[host] || s3_source[host.to_sym]
    raise FetchError.new("no key for host #{host} in s3_source in .gemrc", "s3://#{host}") unless auth

    provider = auth[:provider] || auth['provider']
    case provider
    when 'env'
      id = ENV['AWS_ACCESS_KEY_ID']
      secret = ENV['AWS_SECRET_ACCESS_KEY']
      security_token = ENV['AWS_SESSION_TOKEN']
    when 'instance_profile'
      require 'json'
      credentials_response = fetch_http URI(EC2_METADATA_CREDENTIALS)
      credentials = JSON.parse(credentials_response)
      id = credentials['AccessKeyId']
      secret = credentials['SecretAccessKey']
      security_token = credentials['Token']
    else
      id = auth[:id] || auth['id']
      secret = auth[:secret] || auth['secret']
      raise FetchError.new("s3_source for #{host} missing id or secret", "s3://#{host}") unless id && secret

      security_token = auth[:security_token] || auth['security_token']
    end

    region = auth[:region] || auth['region'] || 'us-east-1'
    S3Config.new(id, secret, security_token, region)
  end

  EC2_METADATA_CREDENTIALS = "http://169.254.169.254/latest/meta-data/identity-credentials/ec2/security-credentials/ec2-instance"

end
