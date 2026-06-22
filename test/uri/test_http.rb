# frozen_string_literal: false
require 'test/unit'
require 'uri/http'
require 'uri/https'

class URI::TestHTTP < Test::Unit::TestCase
  def setup
  end

  def teardown
  end

  def uri_to_ary(uri)
    uri.class.component.collect {|c| uri.send(c)}
  end

  def test_build
    u = URI::HTTP.build(host: 'www.example.com', path: '/foo/bar')
    assert_kind_of(URI::HTTP, u)
  end

  def test_build_empty_host
    assert_raise(URI::InvalidComponentError) { URI::HTTP.build(host: '') }
  end

  def test_parse
    u = URI.parse('http://a')
    assert_kind_of(URI::HTTP, u)
    assert_equal([
      'http',
      nil, 'a', URI::HTTP.default_port,
      '', nil, nil
    ], uri_to_ary(u))
  end

  def test_normalize
    host = 'aBcD'
    u1 = URI.parse('http://' + host + '/eFg?HiJ')
    u2 = URI.parse('http://' + host.downcase + '/eFg?HiJ')
    assert_equal('abcd', u1.normalize.host)
    assert_equal(u1.path, u1.normalize.path)
    assert_equal(u2.normalize, u1.normalize)
    refute_same(u1.host, u1.normalize.host)
    assert_same(u2.host, u2.normalize.host)

    assert_equal('http://abc/', URI.parse('http://abc').normalize.to_s)
  end

  def test_equal
    assert_equal(URI.parse('http://ABC'), URI.parse('http://abc'))
    assert_equal(URI.parse('http://ABC/def'), URI.parse('http://abc/def'))
    refute_equal(URI.parse('http://ABC/DEF'), URI.parse('http://abc/def'))
  end

  def test_request_uri
    assert_equal('/', URI.parse('http://a.b.c/').request_uri)
    assert_equal('/?abc=def', URI.parse('http://a.b.c/?abc=def').request_uri)
    assert_equal('/', URI.parse('http://a.b.c').request_uri)
    assert_equal('/?abc=def', URI.parse('http://a.b.c?abc=def').request_uri)
    assert_equal(nil, URI.parse('http:foo').request_uri)
  end

  def test_select
    assert_equal(['http', 'a.b.c', 80], URI.parse('http://a.b.c/').select(:scheme, :host, :port))
    u = URI.parse('http://a.b.c/')
    assert_equal(uri_to_ary(u), u.select(*u.component))
    assert_raise(ArgumentError) do
      u.select(:scheme, :host, :not_exist, :port)
    end
  end

  def test_authority
    assert_equal('a.b.c', URI.parse('http://a.b.c/').authority)
    assert_equal('a.b.c:8081', URI.parse('http://a.b.c:8081/').authority)
    assert_equal('a.b.c', URI.parse('http://a.b.c:80/').authority)
  end


  def test_origin
    assert_equal('http://a.b.c', URI.parse('http://a.b.c/').origin)
    assert_equal('http://a.b.c:8081', URI.parse('http://a.b.c:8081/').origin)
    assert_equal('http://a.b.c', URI.parse('http://a.b.c:80/').origin)
    assert_equal('https://a.b.c', URI.parse('https://a.b.c/').origin)
  end
end
