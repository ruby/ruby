require 'rubygems/test_case'
require 'rubygems/request'
require 'ostruct'

class TestGemRequest < Gem::TestCase

  def setup
    @proxies = %w[http_proxy HTTP_PROXY http_proxy_user HTTP_PROXY_USER http_proxy_pass HTTP_PROXY_PASS no_proxy NO_PROXY]
    @old_proxies = @proxies.map {|k| ENV[k] }
    @proxies.each {|k| ENV[k] = nil }

    super

    @proxy_uri = "http://localhost:1234"

    @request = Gem::Request.new nil, nil, nil, nil
  end

  def teardown
    super
    Gem.configuration[:http_proxy] = nil
    @proxies.each_with_index {|k, i| ENV[k] = @old_proxies[i] }
  end

  def test_initialize_proxy
    proxy_uri = 'http://proxy.example.com'

    request = Gem::Request.new nil, nil, nil, proxy_uri

    assert_equal proxy_uri, request.proxy_uri.to_s
  end

  def test_initialize_proxy_URI
    proxy_uri = 'http://proxy.example.com'

    request = Gem::Request.new nil, nil, nil, URI(proxy_uri)

    assert_equal proxy_uri, request.proxy_uri.to_s
  end

  def test_initialize_proxy_ENV
    ENV['http_proxy'] = @proxy_uri
    ENV['http_proxy_user'] = 'foo'
    ENV['http_proxy_pass'] = 'bar'

    request = Gem::Request.new nil, nil, nil, nil

    proxy = request.proxy_uri

    assert_equal 'foo', proxy.user
    assert_equal 'bar', proxy.password
  end

  def test_get_proxy_from_env_domain
    ENV['http_proxy'] = @proxy_uri
    ENV['http_proxy_user'] = 'foo\user'
    ENV['http_proxy_pass'] = 'my bar'

    proxy = @request.get_proxy_from_env

    assert_equal 'foo\user', Gem::UriFormatter.new(proxy.user).unescape
    assert_equal 'my bar', Gem::UriFormatter.new(proxy.password).unescape
  end

  def test_get_proxy_from_env_normalize
    ENV['HTTP_PROXY'] = 'fakeurl:12345'

    assert_equal 'http://fakeurl:12345', @request.get_proxy_from_env.to_s
  end

  def test_get_proxy_from_env_empty
    ENV['HTTP_PROXY'] = ''
    ENV.delete 'http_proxy'

    assert_nil @request.get_proxy_from_env
  end

  def test_fetch
    uri = URI.parse "#{@gem_repo}/specs.#{Gem.marshal_version}"
    @request = Gem::Request.new(uri, Net::HTTP::Get, nil, nil)
    util_stub_connection_for :body => :junk, :code => 200

    response = @request.fetch

    assert_equal 200, response.code
    assert_equal :junk, response.body
  end

  def test_fetch_head
    uri = URI.parse "#{@gem_repo}/specs.#{Gem.marshal_version}"
    @request = Gem::Request.new(uri, Net::HTTP::Get, nil, nil)
    util_stub_connection_for :body => '', :code => 200

    response = @request.fetch

    assert_equal 200, response.code
    assert_equal '', response.body
  end

  def test_fetch_unmodified
    uri = URI.parse "#{@gem_repo}/specs.#{Gem.marshal_version}"
    t = Time.now
    @request = Gem::Request.new(uri, Net::HTTP::Get, t, nil)
    conn = util_stub_connection_for :body => '', :code => 304

    response = @request.fetch

    assert_equal 304, response.code
    assert_equal '', response.body

    assert_equal t.rfc2822, conn.payload['if-modified-since']
  end

  def test_user_agent
    ua = Gem::Request.new(nil, nil, nil, nil).user_agent

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

    ua = Gem::Request.new(nil, nil, nil, nil).user_agent

    assert_match %r%\) vroom%, ua
  ensure
    util_restore_version
  end

  def test_user_agent_engine_ruby
    util_save_version

    Object.send :remove_const, :RUBY_ENGINE if defined?(RUBY_ENGINE)
    Object.send :const_set,    :RUBY_ENGINE, 'ruby'

    ua = Gem::Request.new(nil, nil, nil, nil).user_agent

    assert_match %r%\)%, ua
  ensure
    util_restore_version
  end

  def test_user_agent_patchlevel
    util_save_version

    Object.send :remove_const, :RUBY_PATCHLEVEL
    Object.send :const_set,    :RUBY_PATCHLEVEL, 5

    ua = Gem::Request.new(nil, nil, nil, nil).user_agent

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

    ua = Gem::Request.new(nil, nil, nil, nil).user_agent

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

    ua = Gem::Request.new(nil, nil, nil, nil).user_agent

    assert_match %r%\(#{Regexp.escape RUBY_RELEASE_DATE}\)%, ua
  ensure
    util_restore_version
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

  def util_stub_connection_for hash
    def @request.connection= conn
      @conn = conn
    end

    def @request.connection_for uri
      @conn
    end

    @request.connection = Conn.new OpenStruct.new(hash)
  end

  class Conn
    attr_accessor :payload

    def initialize(response)
      @response = response
      self.payload = nil
    end

    def request(req)
      self.payload = req
      @response
    end
  end

end

