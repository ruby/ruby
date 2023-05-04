# frozen_string_literal: false
require 'test/unit'
require 'uri/http'
require 'uri/ws'

class URI::TestWS < Test::Unit::TestCase
  def setup
  end

  def teardown
  end

  def uri_to_ary(uri)
    uri.class.component.collect {|c| uri.send(c)}
  end

  def test_build
    u = URI::WS.build(host: 'www.example.com', path: '/foo/bar')
    assert_kind_of(URI::WS, u)
  end

  def test_parse
    u = URI.parse('ws://a')
    assert_kind_of(URI::WS, u)
    assert_equal(['ws',
		   nil, 'a', URI::HTTP.default_port,
		   '', nil], uri_to_ary(u))
  end

  def test_normalize
    host = 'aBcD'
    u1 = URI.parse('ws://' + host          + '/eFg?HiJ')
    u2 = URI.parse('ws://' + host.downcase + '/eFg?HiJ')
    assert(u1.normalize.host == 'abcd')
    assert(u1.normalize.path == u1.path)
    assert(u1.normalize == u2.normalize)
    assert(!u1.normalize.host.equal?(u1.host))
    assert( u2.normalize.host.equal?(u2.host))

    assert_equal('ws://abc/', URI.parse('ws://abc').normalize.to_s)
  end

  def test_equal
    assert(URI.parse('ws://abc') == URI.parse('ws://ABC'))
    assert(URI.parse('ws://abc/def') == URI.parse('ws://ABC/def'))
    assert(URI.parse('ws://abc/def') != URI.parse('ws://ABC/DEF'))
  end

  def test_request_uri
    assert_equal('/',         URI.parse('ws://a.b.c/').request_uri)
    assert_equal('/?abc=def', URI.parse('ws://a.b.c/?abc=def').request_uri)
    assert_equal('/',         URI.parse('ws://a.b.c').request_uri)
    assert_equal('/?abc=def', URI.parse('ws://a.b.c?abc=def').request_uri)
    assert_equal(nil,         URI.parse('ws:foo').request_uri)
  end

  def test_select
    assert_equal(['ws', 'a.b.c', 80], URI.parse('ws://a.b.c/').select(:scheme, :host, :port))
    u = URI.parse('ws://a.b.c/')
    assert_equal(uri_to_ary(u), u.select(*u.component))
    assert_raise(ArgumentError) do
      u.select(:scheme, :host, :not_exist, :port)
    end
  end
end
