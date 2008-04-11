require 'net/http'
require 'uri'

require 'rubygems'

##
# RemoteFetcher handles the details of fetching gems and gem information from
# a remote source.

class Gem::RemoteFetcher

  include Gem::UserInteraction

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
    Socket.do_not_reverse_lookup = true

    @connections = {}
    @requests = Hash.new 0
    @proxy_uri =
      case proxy
      when :no_proxy then nil
      when nil then get_proxy_from_env
      when URI::HTTP then proxy
      else URI.parse(proxy)
      end
  end

  ##
  # Moves the gem +spec+ from +source_uri+ to the cache dir unless it is
  # already there.  If the source_uri is local the gem cache dir copy is
  # always replaced.
  def download(spec, source_uri, install_dir = Gem.dir)
    gem_file_name = "#{spec.full_name}.gem"
    local_gem_path = File.join install_dir, 'cache', gem_file_name

    Gem.ensure_gem_subdirectories install_dir

    source_uri = URI.parse source_uri unless URI::Generic === source_uri
    scheme = source_uri.scheme

    # URI.parse gets confused by MS Windows paths with forward slashes.
    scheme = nil if scheme =~ /^[a-z]$/i

    case scheme
    when 'http' then
      unless File.exist? local_gem_path then
        begin
          say "Downloading gem #{gem_file_name}" if
            Gem.configuration.really_verbose

          remote_gem_path = source_uri + "gems/#{gem_file_name}"

          gem = Gem::RemoteFetcher.fetcher.fetch_path remote_gem_path
        rescue Gem::RemoteFetcher::FetchError
          raise if spec.original_platform == spec.platform

          alternate_name = "#{spec.original_name}.gem"

          say "Failed, downloading gem #{alternate_name}" if
            Gem.configuration.really_verbose

          remote_gem_path = source_uri + "gems/#{alternate_name}"

          gem = Gem::RemoteFetcher.fetcher.fetch_path remote_gem_path
        end

        File.open local_gem_path, 'wb' do |fp|
          fp.write gem
        end
      end
    when nil, 'file' then # TODO test for local overriding cache
      begin
        FileUtils.cp source_uri.to_s, local_gem_path
      rescue Errno::EACCES
        local_gem_path = source_uri.to_s
      end

      say "Using local gem #{local_gem_path}" if
        Gem.configuration.really_verbose
    else
      raise Gem::InstallError, "unsupported URI scheme #{source_uri.scheme}"
    end

    local_gem_path
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
  rescue => e
    message = "#{e.class}: #{e} reading #{uri}"
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
    raise Gem::RemoteFetcher::FetchError,
          "#{e.message} (#{e.class})\n\tgetting size of #{uri}"
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
  def open_uri_or_path(uri, depth = 0, &block)
    if file_uri?(uri)
      open(get_file_uri_path(uri), &block)
    else
      uri = URI.parse uri unless URI::Generic === uri
      net_http_args = [uri.host, uri.port]

      if @proxy_uri then
        net_http_args += [  @proxy_uri.host,
                            @proxy_uri.port,
                            @proxy_uri.user,
                            @proxy_uri.password
        ]
      end

      connection_id = net_http_args.join ':'
      @connections[connection_id] ||= Net::HTTP.new(*net_http_args)
      connection = @connections[connection_id]

      if uri.scheme == 'https' && ! connection.started?
        http_obj.use_ssl = true
        http_obj.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      connection.start unless connection.started?

      request = Net::HTTP::Get.new(uri.request_uri)
      unless uri.nil? || uri.user.nil? || uri.user.empty? then
        request.basic_auth(uri.user, uri.password)
      end

      ua = "RubyGems/#{Gem::RubyGemsVersion} #{Gem::Platform.local}"
      ua << " Ruby/#{RUBY_VERSION} (#{RUBY_RELEASE_DATE}"
      ua << " patchlevel #{RUBY_PATCHLEVEL}" if defined? RUBY_PATCHLEVEL
      ua << ")"

      request.add_field 'User-Agent', ua
      request.add_field 'Connection', 'keep-alive'
      request.add_field 'Keep-Alive', '30'

      # HACK work around EOFError bug in Net::HTTP
      # NOTE Errno::ECONNABORTED raised a lot on Windows, and make impossible
      # to install gems.
      retried = false
      begin
        @requests[connection_id] += 1
        response = connection.request(request)
      rescue EOFError, Errno::ECONNABORTED
        requests = @requests[connection_id]
        say "connection reset after #{requests} requests, retrying" if
          Gem.configuration.really_verbose

        raise Gem::RemoteFetcher::FetchError, 'too many connection resets' if
          retried

        @requests[connection_id] = 0

        connection.finish
        connection.start
        retried = true
        retry
      end

      case response
      when Net::HTTPOK then
        block.call(StringIO.new(response.body)) if block
      when Net::HTTPRedirection then
        raise Gem::RemoteFetcher::FetchError, "too many redirects" if depth > 10
        open_uri_or_path(response['Location'], depth + 1, &block)
      else
        raise Gem::RemoteFetcher::FetchError,
              "bad response #{response.message} #{response.code}"
      end
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

