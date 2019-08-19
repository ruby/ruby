# frozen_string_literal: true
require 'net/http'
require 'time'
require 'rubygems/user_interaction'

class Gem::Request

  extend Gem::UserInteraction
  include Gem::UserInteraction

  ###
  # Legacy.  This is used in tests.
  def self.create_with_proxy(uri, request_class, last_modified, proxy) # :nodoc:
    cert_files = get_cert_files
    proxy ||= get_proxy_from_env(uri.scheme)
    pool       = ConnectionPools.new proxy_uri(proxy), cert_files

    new(uri, request_class, last_modified, pool.pool_for(uri))
  end

  def self.proxy_uri(proxy) # :nodoc:
    case proxy
    when :no_proxy then nil
    when URI::HTTP then proxy
    else URI.parse(proxy)
    end
  end

  def initialize(uri, request_class, last_modified, pool)
    @uri = uri
    @request_class = request_class
    @last_modified = last_modified
    @requests = Hash.new 0
    @user_agent = user_agent

    @connection_pool = pool
  end

  def proxy_uri; @connection_pool.proxy_uri; end
  def cert_files; @connection_pool.cert_files; end

  def self.get_cert_files
    pattern = File.expand_path("./ssl_certs/*/*.pem", File.dirname(__FILE__))
    Dir.glob(pattern)
  end

  def self.configure_connection_for_https(connection, cert_files)
    require 'net/https'
    connection.use_ssl = true
    connection.verify_mode =
      Gem.configuration.ssl_verify_mode || OpenSSL::SSL::VERIFY_PEER
    store = OpenSSL::X509::Store.new

    if Gem.configuration.ssl_client_cert
      pem = File.read Gem.configuration.ssl_client_cert
      connection.cert = OpenSSL::X509::Certificate.new pem
      connection.key = OpenSSL::PKey::RSA.new pem
    end

    store.set_default_paths
    cert_files.each do |ssl_cert_file|
      store.add_file ssl_cert_file
    end
    if Gem.configuration.ssl_ca_cert
      if File.directory? Gem.configuration.ssl_ca_cert
        store.add_path Gem.configuration.ssl_ca_cert
      else
        store.add_file Gem.configuration.ssl_ca_cert
      end
    end
    connection.cert_store = store

    connection.verify_callback = proc do |preverify_ok, store_context|
      verify_certificate store_context unless preverify_ok

      preverify_ok
    end

    connection
  rescue LoadError => e
    raise unless (e.respond_to?(:path) && e.path == 'openssl') ||
                 e.message =~ / -- openssl$/

    raise Gem::Exception.new(
            'Unable to require openssl, install OpenSSL and rebuild Ruby (preferred) or use non-HTTPS sources')
  end

  def self.verify_certificate(store_context)
    depth  = store_context.error_depth
    error  = store_context.error_string
    number = store_context.error
    cert   = store_context.current_cert

    ui.alert_error "SSL verification error at depth #{depth}: #{error} (#{number})"

    extra_message = verify_certificate_message number, cert

    ui.alert_error extra_message if extra_message
  end

  def self.verify_certificate_message(error_number, cert)
    return unless cert
    case error_number
    when OpenSSL::X509::V_ERR_CERT_HAS_EXPIRED then
      "Certificate #{cert.subject} expired at #{cert.not_after.iso8601}"
    when OpenSSL::X509::V_ERR_CERT_NOT_YET_VALID then
      "Certificate #{cert.subject} not valid until #{cert.not_before.iso8601}"
    when OpenSSL::X509::V_ERR_CERT_REJECTED then
      "Certificate #{cert.subject} is rejected"
    when OpenSSL::X509::V_ERR_CERT_UNTRUSTED then
      "Certificate #{cert.subject} is not trusted"
    when OpenSSL::X509::V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT then
      "Certificate #{cert.issuer} is not trusted"
    when OpenSSL::X509::V_ERR_INVALID_CA then
      "Certificate #{cert.subject} is an invalid CA certificate"
    when OpenSSL::X509::V_ERR_INVALID_PURPOSE then
      "Certificate #{cert.subject} has an invalid purpose"
    when OpenSSL::X509::V_ERR_SELF_SIGNED_CERT_IN_CHAIN then
      "Root certificate is not trusted (#{cert.subject})"
    when OpenSSL::X509::V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY then
      "You must add #{cert.issuer} to your local trusted store"
    when
      OpenSSL::X509::V_ERR_UNABLE_TO_VERIFY_LEAF_SIGNATURE then
      "Cannot verify certificate issued by #{cert.issuer}"
    end
  end

  ##
  # Creates or an HTTP connection based on +uri+, or retrieves an existing
  # connection, using a proxy if needed.

  def connection_for(uri)
    @connection_pool.checkout
  rescue defined?(OpenSSL::SSL) ? OpenSSL::SSL::SSLError : Errno::EHOSTDOWN,
         Errno::EHOSTDOWN => e
    raise Gem::RemoteFetcher::FetchError.new(e.message, uri)
  end

  def fetch
    request = @request_class.new @uri.request_uri

    unless @uri.nil? || @uri.user.nil? || @uri.user.empty?
      request.basic_auth Gem::UriFormatter.new(@uri.user).unescape,
                         Gem::UriFormatter.new(@uri.password).unescape
    end

    request.add_field 'User-Agent', @user_agent
    request.add_field 'Connection', 'keep-alive'
    request.add_field 'Keep-Alive', '30'

    if @last_modified
      request.add_field 'If-Modified-Since', @last_modified.httpdate
    end

    yield request if block_given?

    perform_request request
  end

  ##
  # Returns a proxy URI for the given +scheme+ if one is set in the
  # environment variables.

  def self.get_proxy_from_env(scheme = 'http')
    _scheme = scheme.downcase
    _SCHEME = scheme.upcase
    env_proxy = ENV["#{_scheme}_proxy"] || ENV["#{_SCHEME}_PROXY"]

    no_env_proxy = env_proxy.nil? || env_proxy.empty?

    return get_proxy_from_env 'http' if no_env_proxy and _scheme != 'http'
    return :no_proxy                 if no_env_proxy

    uri = URI(Gem::UriFormatter.new(env_proxy).normalize)

    if uri and uri.user.nil? and uri.password.nil?
      user     = ENV["#{_scheme}_proxy_user"] || ENV["#{_SCHEME}_PROXY_USER"]
      password = ENV["#{_scheme}_proxy_pass"] || ENV["#{_SCHEME}_PROXY_PASS"]

      uri.user     = Gem::UriFormatter.new(user).escape
      uri.password = Gem::UriFormatter.new(password).escape
    end

    uri
  end

  def perform_request(request) # :nodoc:
    connection = connection_for @uri

    retried = false
    bad_response = false

    begin
      @requests[connection.object_id] += 1

      verbose "#{request.method} #{@uri}"

      file_name = File.basename(@uri.path)
      # perform download progress reporter only for gems
      if request.response_body_permitted? && file_name =~ /\.gem$/
        reporter = ui.download_reporter
        response = connection.request(request) do |incomplete_response|
          if Net::HTTPOK === incomplete_response
            reporter.fetch(file_name, incomplete_response.content_length)
            downloaded = 0
            data = String.new

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

      verbose "#{response.code} #{response.message}"

    rescue Net::HTTPBadResponse
      verbose "bad response"

      reset connection

      raise Gem::RemoteFetcher::FetchError.new('too many bad responses', @uri) if bad_response

      bad_response = true
      retry
    rescue Net::HTTPFatalError
      verbose "fatal error"

      raise Gem::RemoteFetcher::FetchError.new('fatal error', @uri)
    # HACK work around EOFError bug in Net::HTTP
    # NOTE Errno::ECONNABORTED raised a lot on Windows, and make impossible
    # to install gems.
    rescue EOFError, Timeout::Error,
           Errno::ECONNABORTED, Errno::ECONNRESET, Errno::EPIPE

      requests = @requests[connection.object_id]
      verbose "connection reset after #{requests} requests, retrying"

      raise Gem::RemoteFetcher::FetchError.new('too many connection resets', @uri) if retried

      reset connection

      retried = true
      retry
    end

    response
  ensure
    @connection_pool.checkin connection
  end

  ##
  # Resets HTTP connection +connection+.

  def reset(connection)
    @requests.delete connection.object_id

    connection.finish
    connection.start
  end

  def user_agent
    ua = "RubyGems/#{Gem::VERSION} #{Gem::Platform.local}".dup

    ruby_version = RUBY_VERSION
    ruby_version += 'dev' if RUBY_PATCHLEVEL == -1

    ua << " Ruby/#{ruby_version} (#{RUBY_RELEASE_DATE}"
    if RUBY_PATCHLEVEL >= 0
      ua << " patchlevel #{RUBY_PATCHLEVEL}"
    elsif defined?(RUBY_REVISION)
      ua << " revision #{RUBY_REVISION}"
    end
    ua << ")"

    ua << " #{RUBY_ENGINE}" if defined?(RUBY_ENGINE) and RUBY_ENGINE != 'ruby'

    ua
  end

end

require 'rubygems/request/http_pool'
require 'rubygems/request/https_pool'
require 'rubygems/request/connection_pools'
