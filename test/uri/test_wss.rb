# frozen_string_literal: false
require 'test/unit'
require 'uri/https'
require 'uri/wss'

class URI::TestWSS < Test::Unit::TestCase
  def setup
  end

  def teardown
  end

  def uri_to_ary(uri)
    uri.class.component.collect {|c| uri.send(c)}
  end

  def test_build
    u = URI::WSS.build(host: 'www.example.com', path: '/foo/bar')
    assert_kind_of(URI::WSS, u)
  end

  def test_parse
    u = URI.parse('wss://a')
    assert_kind_of(URI::WSS, u)
    assert_equal(['wss',
		   nil, 'a', URI::HTTPS.default_port,
		   '', nil], uri_to_ary(u))
  end

  def test_normalize
    host = 'aBcD'
    u1 = URI.parse('wss://' + host          + '/eFg?HiJ')
    u2 = URI.parse('wss://' + host.downcase + '/eFg?HiJ')
    assert(u1.normalize.host == 'abcd')
    assert(u1.normalize.path == u1.path)
    assert(u1.normalize == u2.normalize)
    assert(!u1.normalize.host.equal?(u1.host))
    assert( u2.normalize.host.equal?(u2.host))

    assert_equal('wss://abc/', URI.parse('wss://abc').normalize.to_s)
  end

  def test_equal
    assert(URI.parse('wss://abc') == URI.parse('wss://ABC'))
    assert(URI.parse('wss://abc/def') == URI.parse('wss://ABC/def'))
    assert(URI.parse('wss://abc/def') != URI.parse('wss://ABC/DEF'))
  end

  def test_request_uri
    assert_equal('/',         URI.parse('wss://a.b.c/').request_uri)
    assert_equal('/?abc=def', URI.parse('wss://a.b.c/?abc=def').request_uri)
    assert_equal('/',         URI.parse('wss://a.b.c').request_uri)
    assert_equal('/?abc=def', URI.parse('wss://a.b.c?abc=def').request_uri)
    assert_equal(nil,         URI.parse('wss:foo').request_uri)
  end

  def test_select
    assert_equal(['wss', 'a.b.c', 443], URI.parse('wss://a.b.c/').select(:scheme, :host, :port))
    u = URI.parse('wss://a.b.c/')
    assert_equal(uri_to_ary(u), u.select(*u.component))
    assert_raise(ArgumentError) do
      u.select(:scheme, :host, :not_exist, :port)
    end
  end
end
