require 'net/http'
require 'thread'
require 'time'
require 'rubygems/user_interaction'

class Gem::Request

  include Gem::UserInteraction

  attr_reader :proxy_uri

  def initialize(uri, request_class, last_modified, proxy)
    @uri = uri
    @request_class = request_class
    @last_modified = last_modified
    @requests = Hash.new 0
    @connections = {}
    @connections_mutex = Mutex.new
    @user_agent = user_agent

    @proxy_uri =
      case proxy
      when :no_proxy then nil
      when nil       then get_proxy_from_env uri.scheme
      when URI::HTTP then proxy
      else URI.parse(proxy)
      end
    @env_no_proxy = get_no_proxy_from_env
  end

  def add_rubygems_trusted_certs(store)
    pattern = File.expand_path("./ssl_certs/*.pem", File.dirname(__FILE__))
    Dir.glob(pattern).each do |ssl_cert_file|
      store.add_file ssl_cert_file
    end
  end

  def configure_connection_for_https(connection)
    require 'net/https'
    connection.use_ssl = true
    connection.verify_mode =
      Gem.configuration.ssl_verify_mode || OpenSSL::SSL::VERIFY_PEER
    store = OpenSSL::X509::Store.new

    if Gem.configuration.ssl_client_cert then
      pem = File.read Gem.configuration.ssl_client_cert
      connection.cert = OpenSSL::X509::Certificate.new pem
      connection.key = OpenSSL::PKey::RSA.new pem
    end

    store.set_default_paths
    add_rubygems_trusted_certs(store)
    if Gem.configuration.ssl_ca_cert
      if File.directory? Gem.configuration.ssl_ca_cert
        store.add_path Gem.configuration.ssl_ca_cert
      else
        store.add_file Gem.configuration.ssl_ca_cert
      end
    end
    connection.cert_store = store
  rescue LoadError => e
    raise unless (e.respond_to?(:path) && e.path == 'openssl') ||
                 e.message =~ / -- openssl$/

    raise Gem::Exception.new(
            'Unable to require openssl, install OpenSSL and rebuild ruby (preferred) or use non-HTTPS sources')
  end

  ##
  # Creates or an HTTP connection based on +uri+, or retrieves an existing
  # connection, using a proxy if needed.

  def connection_for(uri)
    net_http_args = [uri.host, uri.port]

    if @proxy_uri and not no_proxy?(uri.host) then
      net_http_args += [
        @proxy_uri.host,
        @proxy_uri.port,
        Gem::UriFormatter.new(@proxy_uri.user).unescape,
        Gem::UriFormatter.new(@proxy_uri.password).unescape,
      ]
    end

    connection_id = [Thread.current.object_id, *net_http_args].join ':'

    connection = @connections_mutex.synchronize do
      @connections[connection_id] ||= Net::HTTP.new(*net_http_args)
      @connections[connection_id]
    end

    if https?(uri) and not connection.started? then
      configure_connection_for_https(connection)
    end

    connection.start unless connection.started?

    connection
  rescue defined?(OpenSSL::SSL) ? OpenSSL::SSL::SSLError : Errno::EHOSTDOWN,
         Errno::EHOSTDOWN => e
    raise Gem::RemoteFetcher::FetchError.new(e.message, uri)
  end

  def fetch
    request = @request_class.new @uri.request_uri

    unless @uri.nil? || @uri.user.nil? || @uri.user.empty? then
      request.basic_auth Gem::UriFormatter.new(@uri.user).unescape,
                         Gem::UriFormatter.new(@uri.password).unescape
    end

    request.add_field 'User-Agent', @user_agent
    request.add_field 'Connection', 'keep-alive'
    request.add_field 'Keep-Alive', '30'

    if @last_modified then
      request.add_field 'If-Modified-Since', @last_modified.httpdate
    end

    yield request if block_given?

    connection = connection_for @uri

    retried = false
    bad_response = false

    begin
      @requests[connection.object_id] += 1

      say "#{request.method} #{@uri}" if
        Gem.configuration.really_verbose

      file_name = File.basename(@uri.path)
      # perform download progress reporter only for gems
      if request.response_body_permitted? && file_name =~ /\.gem$/
        reporter = ui.download_reporter
        response = connection.request(request) do |incomplete_response|
          if Net::HTTPOK === incomplete_response
            reporter.fetch(file_name, incomplete_response.content_length)
            downloaded = 0
            data = ''

            incomplete_response.read_body do |segment|
              data << segment
              downloaded += segment.length
              reporter.update(downloaded)
            end
            reporter.done
            if incomplete_response.respond_to? :body=
              incomplete_response.body = data
            else
              incomplete_response.instance_variable_set(:@body, data)
            end
          end
        end
      else
        response = connection.request request
      end

      say "#{response.code} #{response.message}" if
        Gem.configuration.really_verbose

    rescue Net::HTTPBadResponse
      say "bad response" if Gem.configuration.really_verbose

      reset connection

      raise Gem::RemoteFetcher::FetchError.new('too many bad responses', @uri) if bad_response

      bad_response = true
      retry
    # HACK work around EOFError bug in Net::HTTP
    # NOTE Errno::ECONNABORTED raised a lot on Windows, and make impossible
    # to install gems.
    rescue EOFError, Timeout::Error,
           Errno::ECONNABORTED, Errno::ECONNRESET, Errno::EPIPE

      requests = @requests[connection.object_id]
      say "connection reset after #{requests} requests, retrying" if
        Gem.configuration.really_verbose

      raise Gem::RemoteFetcher::FetchError.new('too many connection resets', @uri) if retried

      reset connection

      retried = true
      retry
    end

    response
  end

  ##
  # Returns list of no_proxy entries (if any) from the environment

  def get_no_proxy_from_env
    env_no_proxy = ENV['no_proxy'] || ENV['NO_PROXY']

    return [] if env_no_proxy.nil?  or env_no_proxy.empty?

    env_no_proxy.split(/\s*,\s*/)
  end

  ##
  # Returns a proxy URI for the given +scheme+ if one is set in the
  # environment variables.

  def get_proxy_from_env scheme = 'http'
    _scheme = scheme.downcase
    _SCHEME = scheme.upcase
    env_proxy = ENV["#{_scheme}_proxy"] || ENV["#{_SCHEME}_PROXY"]

    no_env_proxy = env_proxy.nil? || env_proxy.empty?

    return get_proxy_from_env 'http' if no_env_proxy and _scheme != 'http'
    return nil                       if no_env_proxy

    uri = URI(Gem::UriFormatter.new(env_proxy).normalize)

    if uri and uri.user.nil? and uri.password.nil? then
      user     = ENV["#{_scheme}_proxy_user"] || ENV["#{_SCHEME}_PROXY_USER"]
      password = ENV["#{_scheme}_proxy_pass"] || ENV["#{_SCHEME}_PROXY_PASS"]

      uri.user     = Gem::UriFormatter.new(user).escape
      uri.password = Gem::UriFormatter.new(password).escape
    end

    uri
  end

  def https?(uri)
    uri.scheme.downcase == 'https'
  end

  def no_proxy? host
    host = host.downcase
    @env_no_proxy.each do |pattern|
      pattern = pattern.downcase
      return true if host[-pattern.length, pattern.length ] == pattern
    end
    return false
  end

  ##
  # Resets HTTP connection +connection+.

  def reset(connection)
    @requests.delete connection.object_id

    connection.finish
    connection.start
  end

  def user_agent
    ua = "RubyGems/#{Gem::VERSION} #{Gem::Platform.local}"

    ruby_version = RUBY_VERSION
    ruby_version += 'dev' if RUBY_PATCHLEVEL == -1

    ua << " Ruby/#{ruby_version} (#{RUBY_RELEASE_DATE}"
    if RUBY_PATCHLEVEL >= 0 then
      ua << " patchlevel #{RUBY_PATCHLEVEL}"
    elsif defined?(RUBY_REVISION) then
      ua << " revision #{RUBY_REVISION}"
    end
    ua << ")"

    ua << " #{RUBY_ENGINE}" if defined?(RUBY_ENGINE) and RUBY_ENGINE != 'ruby'

    ua
  end

end

