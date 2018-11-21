# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/request'
require 'ostruct'
require 'base64'

unless defined?(OpenSSL::SSL)
  warn 'Skipping Gem::Request tests.  openssl not found.'
end

class TestGemRequest < Gem::TestCase

  CA_CERT_FILE     = cert_path 'ca'
  CHILD_CERT       = load_cert 'child'
  EXPIRED_CERT     = load_cert 'expired'
  PUBLIC_CERT      = load_cert 'public'
  PUBLIC_CERT_FILE = cert_path 'public'
  SSL_CERT         = load_cert 'ssl'

  def make_request(uri, request_class, last_modified, proxy)
    Gem::Request.create_with_proxy uri, request_class, last_modified, proxy
  end

  def setup
    @proxies = %w[http_proxy https_proxy HTTP_PROXY http_proxy_user HTTP_PROXY_USER http_proxy_pass HTTP_PROXY_PASS no_proxy NO_PROXY]
    @old_proxies = @proxies.map {|k| ENV[k] }
    @proxies.each {|k| ENV[k] = nil }

    super

    @proxy_uri = "http://localhost:1234"
    @uri = URI('http://example')

    @request = make_request @uri, nil, nil, nil
  end

  def teardown
    super
    Gem.configuration[:http_proxy] = nil
    @proxies.each_with_index {|k, i| ENV[k] = @old_proxies[i] }
  end

  def test_initialize_proxy
    proxy_uri = 'http://proxy.example.com'

    request = make_request @uri, nil, nil, proxy_uri

    assert_equal proxy_uri, request.proxy_uri.to_s
  end

  def test_initialize_proxy_URI
    proxy_uri = 'http://proxy.example.com'

    request = make_request @uri, nil, nil, URI(proxy_uri)

    assert_equal proxy_uri, request.proxy_uri.to_s
  end

  def test_initialize_proxy_ENV
    ENV['http_proxy'] = @proxy_uri
    ENV['http_proxy_user'] = 'foo'
    ENV['http_proxy_pass'] = 'bar'

    request = make_request @uri, nil, nil, nil

    proxy = request.proxy_uri

    assert_equal 'foo', proxy.user
    assert_equal 'bar', proxy.password
  end

  def test_initialize_proxy_ENV_https
    ENV['https_proxy'] = @proxy_uri

    request = make_request URI('https://example'), nil, nil, nil

    proxy = request.proxy_uri

    assert_equal URI(@proxy_uri), proxy
  end

  def test_configure_connection_for_https
    connection = Net::HTTP.new 'localhost', 443

    request = Class.new(Gem::Request) {
      def self.get_cert_files
        [TestGemRequest::PUBLIC_CERT_FILE]
      end
    }.create_with_proxy URI('https://example'), nil, nil, nil

    Gem::Request.configure_connection_for_https connection, request.cert_files

    cert_store = connection.cert_store

    assert cert_store.verify CHILD_CERT
  end

  def test_configure_connection_for_https_ssl_ca_cert
    ssl_ca_cert, Gem.configuration.ssl_ca_cert =
      Gem.configuration.ssl_ca_cert, CA_CERT_FILE

    connection = Net::HTTP.new 'localhost', 443

    request = Class.new(Gem::Request) {
      def self.get_cert_files
        [TestGemRequest::PUBLIC_CERT_FILE]
      end
    }.create_with_proxy URI('https://example'), nil, nil, nil

    Gem::Request.configure_connection_for_https connection, request.cert_files

    cert_store = connection.cert_store

    assert cert_store.verify CHILD_CERT
    assert cert_store.verify SSL_CERT
  ensure
    Gem.configuration.ssl_ca_cert = ssl_ca_cert
  end

  def test_get_proxy_from_env_fallback
    ENV['http_proxy'] = @proxy_uri
    request = make_request @uri, nil, nil, nil
    proxy = request.proxy_uri

    assert_equal URI(@proxy_uri), proxy
  end

  def test_get_proxy_from_env_https
    ENV['https_proxy'] = @proxy_uri
    uri = URI('https://example')
    request = make_request uri, nil, nil, nil

    proxy = request.proxy_uri

    assert_equal URI(@proxy_uri), proxy
  end

  def test_get_proxy_from_env_domain
    ENV['http_proxy'] = @proxy_uri
    ENV['http_proxy_user'] = 'foo\user'
    ENV['http_proxy_pass'] = 'my bar'
    request = make_request @uri, nil, nil, nil

    proxy = request.proxy_uri

    assert_equal 'foo\user', Gem::UriFormatter.new(proxy.user).unescape
    assert_equal 'my bar', Gem::UriFormatter.new(proxy.password).unescape
  end

  def test_get_proxy_from_env_escape
    ENV['http_proxy'] = @proxy_uri
    ENV['http_proxy_user'] = 'foo@user'
    ENV['http_proxy_pass'] = 'my@bar'
    request = make_request @uri, nil, nil, nil

    proxy = request.proxy_uri

    assert_equal 'foo%40user', proxy.user
    assert_equal 'my%40bar',   proxy.password
  end

  def test_get_proxy_from_env_normalize
    ENV['HTTP_PROXY'] = 'fakeurl:12345'
    request = make_request @uri, nil, nil, nil

    assert_equal 'http://fakeurl:12345', request.proxy_uri.to_s
  end

  def test_get_proxy_from_env_empty
    ENV['HTTP_PROXY'] = ''
    ENV.delete 'http_proxy'
    request = make_request @uri, nil, nil, nil

    assert_nil request.proxy_uri
  end

  def test_fetch
    uri = URI.parse "#{@gem_repo}/specs.#{Gem.marshal_version}"
    response = util_stub_net_http(:body => :junk, :code => 200) do
      @request = make_request(uri, Net::HTTP::Get, nil, nil)

      @request.fetch
    end

    assert_equal 200, response.code
    assert_equal :junk, response.body
  end

  def test_fetch_basic_auth
    uri = URI.parse "https://user:pass@example.rubygems/specs.#{Gem.marshal_version}"
    conn = util_stub_net_http(:body => :junk, :code => 200) do |c|
      @request = make_request(uri, Net::HTTP::Get, nil, nil)
      @request.fetch
      c
    end

    auth_header = conn.payload['Authorization']
    assert_equal "Basic #{Base64.encode64('user:pass')}".strip, auth_header
  end

  def test_fetch_basic_auth_encoded
    uri = URI.parse "https://user:%7BDEScede%7Dpass@example.rubygems/specs.#{Gem.marshal_version}"
    conn = util_stub_net_http(:body => :junk, :code => 200) do |c|
      @request = make_request(uri, Net::HTTP::Get, nil, nil)
      @request.fetch
      c
    end

    auth_header = conn.payload['Authorization']
    assert_equal "Basic #{Base64.encode64('user:{DEScede}pass')}".strip, auth_header
  end

  def test_fetch_head
    uri = URI.parse "#{@gem_repo}/specs.#{Gem.marshal_version}"
    response = util_stub_net_http(:body => '', :code => 200) do |conn|
      @request = make_request(uri, Net::HTTP::Get, nil, nil)
      @request.fetch
    end

    assert_equal 200, response.code
    assert_equal '', response.body
  end

  def test_fetch_unmodified
    uri = URI.parse "#{@gem_repo}/specs.#{Gem.marshal_version}"
    t = Time.utc(2013, 1, 2, 3, 4, 5)
    conn, response = util_stub_net_http(:body => '', :code => 304) do |c|
      @request = make_request(uri, Net::HTTP::Get, t, nil)
      [c, @request.fetch]
    end

    assert_equal 304, response.code
    assert_equal '', response.body

    modified_header = conn.payload['if-modified-since']

    assert_equal 'Wed, 02 Jan 2013 03:04:05 GMT', modified_header
  end

  def test_user_agent
    ua = make_request(@uri, nil, nil, nil).user_agent

    assert_match %r%^RubyGems/\S+ \S+ Ruby/\S+ \(.*?\)%,          ua
    assert_match %r%RubyGems/#{Regexp.escape Gem::VERSION}%,      ua
    assert_match %r% #{Regexp.escape Gem::Platform.local.to_s} %, ua
    assert_match %r%Ruby/#{Regexp.escape RUBY_VERSION}%,          ua
    assert_match %r%\(#{Regexp.escape RUBY_RELEASE_DATE} %,       ua
  end

  def test_user_agent_engine
    util_save_version

    Object.send :remove_const, :RUBY_ENGINE if defined?(RUBY_ENGINE)
    Object.send :const_set,    :RUBY_ENGINE, 'vroom'

    ua = make_request(@uri, nil, nil, nil).user_agent

    assert_match %r%\) vroom%, ua
  ensure
    util_restore_version
  end

  def test_user_agent_engine_ruby
    util_save_version

    Object.send :remove_const, :RUBY_ENGINE if defined?(RUBY_ENGINE)
    Object.send :const_set,    :RUBY_ENGINE, 'ruby'

    ua = make_request(@uri, nil, nil, nil).user_agent

    assert_match %r%\)%, ua
  ensure
    util_restore_version
  end

  def test_user_agent_patchlevel
    util_save_version

    Object.send :remove_const, :RUBY_PATCHLEVEL
    Object.send :const_set,    :RUBY_PATCHLEVEL, 5

    ua = make_request(@uri, nil, nil, nil).user_agent

    assert_match %r% patchlevel 5\)%, ua
  ensure
    util_restore_version
  end

  def test_user_agent_revision
    util_save_version

    Object.send :remove_const, :RUBY_PATCHLEVEL
    Object.send :const_set,    :RUBY_PATCHLEVEL, -1
    Object.send :remove_const, :RUBY_REVISION if defined?(RUBY_REVISION)
    Object.send :const_set,    :RUBY_REVISION, 6

    ua = make_request(@uri, nil, nil, nil).user_agent

    assert_match %r% revision 6\)%, ua
    assert_match %r%Ruby/#{Regexp.escape RUBY_VERSION}dev%, ua
  ensure
    util_restore_version
  end

  def test_user_agent_revision_missing
    util_save_version

    Object.send :remove_const, :RUBY_PATCHLEVEL
    Object.send :const_set,    :RUBY_PATCHLEVEL, -1
    Object.send :remove_const, :RUBY_REVISION if defined?(RUBY_REVISION)

    ua = make_request(@uri, nil, nil, nil).user_agent

    assert_match %r%\(#{Regexp.escape RUBY_RELEASE_DATE}\)%, ua
  ensure
    util_restore_version
  end

  def test_verify_certificate
    store = OpenSSL::X509::Store.new
    context = OpenSSL::X509::StoreContext.new store
    context.error = OpenSSL::X509::V_ERR_OUT_OF_MEM

    use_ui @ui do
      Gem::Request.verify_certificate context
    end

    assert_equal "ERROR:  SSL verification error at depth 0: out of memory (17)\n",
                 @ui.error
  end

  def test_verify_certificate_extra_message
    store = OpenSSL::X509::Store.new
    context = OpenSSL::X509::StoreContext.new store
    context.error = OpenSSL::X509::V_ERR_INVALID_CA

    use_ui @ui do
      Gem::Request.verify_certificate context
    end

    expected = <<-ERROR
ERROR:  SSL verification error at depth 0: invalid CA certificate (24)
ERROR:  Certificate  is an invalid CA certificate
    ERROR

    assert_equal expected, @ui.error
  end

  def test_verify_certificate_message_CERT_HAS_EXPIRED
    error_number = OpenSSL::X509::V_ERR_CERT_HAS_EXPIRED

    message =
      Gem::Request.verify_certificate_message error_number, EXPIRED_CERT

    assert_equal "Certificate #{EXPIRED_CERT.subject} expired at #{EXPIRED_CERT.not_before.iso8601}",
                 message
  end

  def test_verify_certificate_message_CERT_NOT_YET_VALID
    error_number = OpenSSL::X509::V_ERR_CERT_NOT_YET_VALID

    message =
      Gem::Request.verify_certificate_message error_number, EXPIRED_CERT

    assert_equal "Certificate #{EXPIRED_CERT.subject} not valid until #{EXPIRED_CERT.not_before.iso8601}",
                 message
  end

  def test_verify_certificate_message_CERT_REJECTED
    error_number = OpenSSL::X509::V_ERR_CERT_REJECTED

    message =
      Gem::Request.verify_certificate_message error_number, CHILD_CERT

    assert_equal "Certificate #{CHILD_CERT.subject} is rejected",
                 message
  end

  def test_verify_certificate_message_CERT_UNTRUSTED
    error_number = OpenSSL::X509::V_ERR_CERT_UNTRUSTED

    message =
      Gem::Request.verify_certificate_message error_number, CHILD_CERT

    assert_equal "Certificate #{CHILD_CERT.subject} is not trusted",
                 message
  end

  def test_verify_certificate_message_DEPTH_ZERO_SELF_SIGNED_CERT
    error_number = OpenSSL::X509::V_ERR_DEPTH_ZERO_SELF_SIGNED_CERT

    message =
      Gem::Request.verify_certificate_message error_number, CHILD_CERT

    assert_equal "Certificate #{CHILD_CERT.issuer} is not trusted",
                 message
  end

  def test_verify_certificate_message_INVALID_CA
    error_number = OpenSSL::X509::V_ERR_INVALID_CA

    message =
      Gem::Request.verify_certificate_message error_number, CHILD_CERT

    assert_equal "Certificate #{CHILD_CERT.subject} is an invalid CA certificate",
                 message
  end

  def test_verify_certificate_message_INVALID_PURPOSE
    error_number = OpenSSL::X509::V_ERR_INVALID_PURPOSE

    message =
      Gem::Request.verify_certificate_message error_number, CHILD_CERT

    assert_equal "Certificate #{CHILD_CERT.subject} has an invalid purpose",
                 message
  end

  def test_verify_certificate_message_SELF_SIGNED_CERT_IN_CHAIN
    error_number = OpenSSL::X509::V_ERR_SELF_SIGNED_CERT_IN_CHAIN

    message =
      Gem::Request.verify_certificate_message error_number, EXPIRED_CERT

    assert_equal "Root certificate is not trusted (#{EXPIRED_CERT.subject})",
                 message
  end

  def test_verify_certificate_message_UNABLE_TO_GET_ISSUER_CERT_LOCALLY
    error_number = OpenSSL::X509::V_ERR_UNABLE_TO_GET_ISSUER_CERT_LOCALLY

    message =
      Gem::Request.verify_certificate_message error_number, EXPIRED_CERT

    assert_equal "You must add #{EXPIRED_CERT.issuer} to your local trusted store",
                 message
  end

  def test_verify_certificate_message_UNABLE_TO_VERIFY_LEAF_SIGNATURE
    error_number = OpenSSL::X509::V_ERR_UNABLE_TO_VERIFY_LEAF_SIGNATURE

    message =
      Gem::Request.verify_certificate_message error_number, EXPIRED_CERT

    assert_equal "Cannot verify certificate issued by #{EXPIRED_CERT.issuer}",
                 message
  end

  def util_restore_version
    Object.send :remove_const, :RUBY_ENGINE if defined?(RUBY_ENGINE)
    Object.send :const_set,    :RUBY_ENGINE, @orig_RUBY_ENGINE if
      defined?(@orig_RUBY_ENGINE)

    Object.send :remove_const, :RUBY_PATCHLEVEL
    Object.send :const_set,    :RUBY_PATCHLEVEL, @orig_RUBY_PATCHLEVEL

    Object.send :remove_const, :RUBY_REVISION if defined?(RUBY_REVISION)
    Object.send :const_set,    :RUBY_REVISION, @orig_RUBY_REVISION if
      defined?(@orig_RUBY_REVISION)
  end

  def util_save_version
    @orig_RUBY_ENGINE     = RUBY_ENGINE if defined? RUBY_ENGINE
    @orig_RUBY_PATCHLEVEL = RUBY_PATCHLEVEL
    @orig_RUBY_REVISION   = RUBY_REVISION if defined? RUBY_REVISION
  end

  def util_stub_net_http(hash)
    old_client = Gem::Request::ConnectionPools.client
    conn = Conn.new OpenStruct.new(hash)
    Gem::Request::ConnectionPools.client = conn
    yield conn
  ensure
    Gem::Request::ConnectionPools.client = old_client
  end

  class Conn
    attr_accessor :payload

    def new(*args); self; end
    def use_ssl=(bool); end
    def verify_callback=(setting); end
    def verify_mode=(setting); end
    def cert_store=(setting); end
    def start; end

    def initialize(response)
      @response = response
      self.payload = nil
    end

    def request(req)
      self.payload = req
      @response
    end
  end

end if defined?(OpenSSL::SSL)
