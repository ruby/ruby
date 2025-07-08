# frozen_string_literal: false
require 'test/unit'
require 'envutil'
require 'uri'

class URI::TestGeneric < Test::Unit::TestCase
  def setup
    @url = 'http://a/b/c/d;p?q'
    @base_url = URI.parse(@url)
  end

  def teardown
  end

  def uri_to_ary(uri)
    uri.class.component.collect {|c| uri.send(c)}
  end

  def test_to_s
    exp = 'http://example.com/'.freeze
    str = URI(exp).to_s
    assert_equal exp, str
    assert_not_predicate str, :frozen?, '[ruby-core:71785] [Bug #11759]'

    assert_equal "file:///foo", URI("file:///foo").to_s
    assert_equal "postgres:///foo", URI("postgres:///foo").to_s
    assert_equal "http:///foo", URI("http:///foo").to_s
    assert_equal "http:/foo", URI("http:/foo").to_s

    uri = URI('rel_path')
    assert_equal "rel_path", uri.to_s
    uri.scheme = 'http'
    assert_equal "http:rel_path", uri.to_s
    uri.host = 'h'
    assert_equal "http://h/rel_path", uri.to_s
    uri.port = 8080
    assert_equal "http://h:8080/rel_path", uri.to_s
    uri.host = nil
    assert_equal "http::8080/rel_path", uri.to_s
  end

  def test_parse
    # 0
    assert_kind_of(URI::HTTP, @base_url)

    exp = [
      'http',
      nil, 'a', URI::HTTP.default_port,
      '/b/c/d;p',
      'q',
      nil
    ]
    ary = uri_to_ary(@base_url)
    assert_equal(exp, ary)

    # 1
    url = URI.parse('ftp://ftp.is.co.za/rfc/rfc1808.txt')
    assert_kind_of(URI::FTP, url)

    exp = [
      'ftp',
      nil, 'ftp.is.co.za', URI::FTP.default_port,
      'rfc/rfc1808.txt', nil,
    ]
    ary = uri_to_ary(url)
    assert_equal(exp, ary)
    # 1'
    url = URI.parse('ftp://ftp.is.co.za/%2Frfc/rfc1808.txt')
    assert_kind_of(URI::FTP, url)

    exp = [
      'ftp',
      nil, 'ftp.is.co.za', URI::FTP.default_port,
      '/rfc/rfc1808.txt', nil,
    ]
    ary = uri_to_ary(url)
    assert_equal(exp, ary)

    # 2
    url = URI.parse('gopher://spinaltap.micro.umn.edu/00/Weather/California/Los%20Angeles')
    assert_kind_of(URI::Generic, url)

    exp = [
      'gopher',
      nil, 'spinaltap.micro.umn.edu', nil, nil,
      '/00/Weather/California/Los%20Angeles', nil,
      nil,
      nil
    ]
    ary = uri_to_ary(url)
    assert_equal(exp, ary)

    # 3
    url = URI.parse('http://www.math.uio.no/faq/compression-faq/part1.html')
    assert_kind_of(URI::HTTP, url)

    exp = [
      'http',
      nil, 'www.math.uio.no', URI::HTTP.default_port,
      '/faq/compression-faq/part1.html',
      nil,
      nil
    ]
    ary = uri_to_ary(url)
    assert_equal(exp, ary)

    # 4
    url = URI.parse('mailto:mduerst@ifi.unizh.ch')
    assert_kind_of(URI::Generic, url)

    exp = [
      'mailto',
      'mduerst@ifi.unizh.ch',
      []
    ]
    ary = uri_to_ary(url)
    assert_equal(exp, ary)

    # 5
    url = URI.parse('news:comp.infosystems.www.servers.unix')
    assert_kind_of(URI::Generic, url)

    exp = [
      'news',
      nil, nil, nil, nil,
      nil, 'comp.infosystems.www.servers.unix',
      nil,
      nil
    ]
    ary = uri_to_ary(url)
    assert_equal(exp, ary)

    # 6
    url = URI.parse('telnet://melvyl.ucop.edu/')
    assert_kind_of(URI::Generic, url)

    exp = [
      'telnet',
      nil, 'melvyl.ucop.edu', nil, nil,
      '/', nil,
      nil,
      nil
    ]
    ary = uri_to_ary(url)
    assert_equal(exp, ary)

    # 7
    # reported by Mr. Kubota <em6t-kbt@asahi-net.or.jp>
    assert_nothing_raised(URI::InvalidURIError) { URI.parse('http://a_b:80/') }
    assert_nothing_raised(URI::InvalidURIError) { URI.parse('http://a_b/') }

    # 8
    # reported by m_seki
    url = URI.parse('file:///foo/bar.txt')
    assert_kind_of(URI::Generic, url)
    url = URI.parse('file:/foo/bar.txt')
    assert_kind_of(URI::Generic, url)

    # 9
    url = URI.parse('ftp://:pass@localhost/')
    assert_equal('', url.user, "[ruby-dev:25667]")
    assert_equal('pass', url.password)
    assert_equal(':pass', url.userinfo, "[ruby-dev:25667]")
    url = URI.parse('ftp://user@localhost/')
    assert_equal('user', url.user)
    assert_equal(nil, url.password)
    assert_equal('user', url.userinfo)
    url = URI.parse('ftp://localhost/')
    assert_equal(nil, url.user)
    assert_equal(nil, url.password)
    assert_equal(nil, url.userinfo)

    # sec-156615
    url = URI.parse('http:////example.com')
    # must be empty string to identify as path-abempty, not path-absolute
    assert_equal('', url.host)
    assert_equal('http:////example.com', url.to_s)

    # sec-2957667
    url = URI.parse('http://user:pass@example.com').merge('//example.net')
    assert_equal('http://example.net', url.to_s)
    assert_nil(url.userinfo)
    url = URI.join('http://user:pass@example.com', '//example.net')
    assert_equal('http://example.net', url.to_s)
    assert_nil(url.userinfo)
    url = URI.parse('http://user:pass@example.com') + '//example.net'
    assert_equal('http://example.net', url.to_s)
    assert_nil(url.userinfo)
  end

  def test_parse_scheme_with_symbols
    # Valid schemes from https://www.iana.org/assignments/uri-schemes/uri-schemes.xhtml
    assert_equal 'ms-search', URI.parse('ms-search://localhost').scheme
    assert_equal 'microsoft.windows.camera', URI.parse('microsoft.windows.camera://localhost').scheme
    assert_equal 'coaps+ws', URI.parse('coaps+ws:localhost').scheme
  end

  def test_merge
    u1 = URI.parse('http://foo')
    u2 = URI.parse('http://foo/')
    u3 = URI.parse('http://foo/bar')
    u4 = URI.parse('http://foo/bar/')

    {
      u1 => {
        'baz'  => 'http://foo/baz',
        '/baz' => 'http://foo/baz',
      },
      u2 => {
        'baz'  => 'http://foo/baz',
        '/baz' => 'http://foo/baz',
      },
      u3 => {
        'baz'  => 'http://foo/baz',
        '/baz' => 'http://foo/baz',
      },
      u4 => {
        'baz'  => 'http://foo/bar/baz',
        '/baz' => 'http://foo/baz',
      },
    }.each { |base, map|
      map.each { |url, result|
        expected = URI.parse(result)
        uri = URI.parse(url)
        assert_equal expected, base + url, "<#{base}> + #{url.inspect} to become <#{expected}>"
        assert_equal expected, base + uri, "<#{base}> + <#{uri}> to become <#{expected}>"
      }
    }

    url = URI.parse('http://hoge/a.html') + 'b.html'
    assert_equal('http://hoge/b.html', url.to_s, "[ruby-dev:11508]")

    # reported by Mr. Kubota <em6t-kbt@asahi-net.or.jp>
    url = URI.parse('http://a/b') + 'http://x/y'
    assert_equal('http://x/y', url.to_s)
    assert_equal(url, URI.parse('')                     + 'http://x/y')
    assert_equal(url, URI.parse('').normalize           + 'http://x/y')
    assert_equal(url, URI.parse('http://a/b').normalize + 'http://x/y')

    u = URI.parse('http://foo/bar/baz')
    assert_equal(nil, u.merge!(""))
    assert_equal(nil, u.merge!(u))
    refute_nil(u.merge!("."))
    assert_equal('http://foo/bar/', u.to_s)
    refute_nil(u.merge!("../baz"))
    assert_equal('http://foo/baz', u.to_s)

    url = URI.parse('http://a/b//c') + 'd//e'
    assert_equal('http://a/b//d//e', url.to_s)

    u0 = URI.parse('mailto:foo@example.com')
    u1 = URI.parse('mailto:foo@example.com#bar')
    assert_equal(uri_to_ary(u0 + '#bar'), uri_to_ary(u1), "[ruby-dev:23628]")

    u0 = URI.parse('http://www.example.com/')
    u1 = URI.parse('http://www.example.com/foo/..') + './'
    assert_equal(u0, u1, "[ruby-list:39838]")
    u0 = URI.parse('http://www.example.com/foo/')
    u1 = URI.parse('http://www.example.com/foo/bar/..') + './'
    assert_equal(u0, u1)
    u0 = URI.parse('http://www.example.com/foo/bar/')
    u1 = URI.parse('http://www.example.com/foo/bar/baz/..') + './'
    assert_equal(u0, u1)
    u0 = URI.parse('http://www.example.com/')
    u1 = URI.parse('http://www.example.com/foo/bar/../..') + './'
    assert_equal(u0, u1)
    u0 = URI.parse('http://www.example.com/foo/')
    u1 = URI.parse('http://www.example.com/foo/bar/baz/../..') + './'
    assert_equal(u0, u1)

    u = URI.parse('http://www.example.com/')
    u0 = u + './foo/'
    u1 = u + './foo/bar/..'
    assert_equal(u0, u1, "[ruby-list:39844]")
    u = URI.parse('http://www.example.com/')
    u0 = u + './'
    u1 = u + './foo/bar/../..'
    assert_equal(u0, u1)
  end

  def test_merge_authority
    u = URI.parse('http://user:pass@example.com:8080')
    u0 = URI.parse('http://new.example.org/path')
    u1 = u.merge('//new.example.org/path')
    assert_equal(u0, u1)
  end

  def test_route
    url = URI.parse('http://hoge/a.html').route_to('http://hoge/b.html')
    assert_equal('b.html', url.to_s)

    url = URI.parse('http://hoge/a/').route_to('http://hoge/b/')
    assert_equal('../b/', url.to_s)
    url = URI.parse('http://hoge/a/b').route_to('http://hoge/b/')
    assert_equal('../b/', url.to_s)

    url = URI.parse('http://hoge/a/b/').route_to('http://hoge/b/')
    assert_equal('../../b/', url.to_s)

    url = URI.parse('http://hoge/a/b/').route_to('http://HOGE/b/')
    assert_equal('../../b/', url.to_s)

    url = URI.parse('http://hoge/a/b/').route_to('http://MOGE/b/')
    assert_equal('//MOGE/b/', url.to_s)

    url = URI.parse('http://hoge/b').route_to('http://hoge/b/')
    assert_equal('b/', url.to_s)
    url = URI.parse('http://hoge/b/a').route_to('http://hoge/b/')
    assert_equal('./', url.to_s)
    url = URI.parse('http://hoge/b/').route_to('http://hoge/b')
    assert_equal('../b', url.to_s)
    url = URI.parse('http://hoge/b').route_to('http://hoge/b:c')
    assert_equal('./b:c', url.to_s)

    url = URI.parse('http://hoge/b//c').route_to('http://hoge/b/c')
    assert_equal('../c', url.to_s)

    url = URI.parse('file:///a/b/').route_to('file:///a/b/')
    assert_equal('', url.to_s)
    url = URI.parse('file:///a/b/').route_to('file:///a/b')
    assert_equal('../b', url.to_s)

    url = URI.parse('mailto:foo@example.com').route_to('mailto:foo@example.com#bar')
    assert_equal('#bar', url.to_s)

    url = URI.parse('mailto:foo@example.com#bar').route_to('mailto:foo@example.com')
    assert_equal('', url.to_s)

    url = URI.parse('mailto:foo@example.com').route_to('mailto:foo@example.com')
    assert_equal('', url.to_s)
  end

  def test_rfc3986_examples
#  http://a/b/c/d;p?q
#        g:h           =  g:h
    url = @base_url.merge('g:h')
    assert_kind_of(URI::Generic, url)
    assert_equal('g:h', url.to_s)
    url = @base_url.route_to('g:h')
    assert_kind_of(URI::Generic, url)
    assert_equal('g:h', url.to_s)

#  http://a/b/c/d;p?q
#        g             =  http://a/b/c/g
    url = @base_url.merge('g')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g', url.to_s)
    url = @base_url.route_to('http://a/b/c/g')
    assert_kind_of(URI::Generic, url)
    assert_equal('g', url.to_s)

#  http://a/b/c/d;p?q
#        ./g           =  http://a/b/c/g
    url = @base_url.merge('./g')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g', url.to_s)
    url = @base_url.route_to('http://a/b/c/g')
    assert_kind_of(URI::Generic, url)
    refute_equal('./g', url.to_s) # ok
    assert_equal('g', url.to_s)

#  http://a/b/c/d;p?q
#        g/            =  http://a/b/c/g/
    url = @base_url.merge('g/')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g/', url.to_s)
    url = @base_url.route_to('http://a/b/c/g/')
    assert_kind_of(URI::Generic, url)
    assert_equal('g/', url.to_s)

#  http://a/b/c/d;p?q
#        /g            =  http://a/g
    url = @base_url.merge('/g')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/g', url.to_s)
    url = @base_url.route_to('http://a/g')
    assert_kind_of(URI::Generic, url)
    refute_equal('/g', url.to_s) # ok
    assert_equal('../../g', url.to_s)

#  http://a/b/c/d;p?q
#        //g           =  http://g
    url = @base_url.merge('//g')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://g', url.to_s)
    url = @base_url.route_to('http://g')
    assert_kind_of(URI::Generic, url)
    assert_equal('//g', url.to_s)

#  http://a/b/c/d;p?q
#        ?y            =  http://a/b/c/d;p?y
    url = @base_url.merge('?y')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/d;p?y', url.to_s)
    url = @base_url.route_to('http://a/b/c/d;p?y')
    assert_kind_of(URI::Generic, url)
    assert_equal('?y', url.to_s)

#  http://a/b/c/d;p?q
#        g?y           =  http://a/b/c/g?y
    url = @base_url.merge('g?y')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g?y', url.to_s)
    url = @base_url.route_to('http://a/b/c/g?y')
    assert_kind_of(URI::Generic, url)
    assert_equal('g?y', url.to_s)

#  http://a/b/c/d;p?q
#        #s            =  http://a/b/c/d;p?q#s
    url = @base_url.merge('#s')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/d;p?q#s', url.to_s)
    url = @base_url.route_to('http://a/b/c/d;p?q#s')
    assert_kind_of(URI::Generic, url)
    assert_equal('#s', url.to_s)

#  http://a/b/c/d;p?q
#        g#s           =  http://a/b/c/g#s
    url = @base_url.merge('g#s')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g#s', url.to_s)
    url = @base_url.route_to('http://a/b/c/g#s')
    assert_kind_of(URI::Generic, url)
    assert_equal('g#s', url.to_s)

#  http://a/b/c/d;p?q
#        g?y#s         =  http://a/b/c/g?y#s
    url = @base_url.merge('g?y#s')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g?y#s', url.to_s)
    url = @base_url.route_to('http://a/b/c/g?y#s')
    assert_kind_of(URI::Generic, url)
    assert_equal('g?y#s', url.to_s)

#  http://a/b/c/d;p?q
#        ;x            =  http://a/b/c/;x
    url = @base_url.merge(';x')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/;x', url.to_s)
    url = @base_url.route_to('http://a/b/c/;x')
    assert_kind_of(URI::Generic, url)
    assert_equal(';x', url.to_s)

#  http://a/b/c/d;p?q
#        g;x           =  http://a/b/c/g;x
    url = @base_url.merge('g;x')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g;x', url.to_s)
    url = @base_url.route_to('http://a/b/c/g;x')
    assert_kind_of(URI::Generic, url)
    assert_equal('g;x', url.to_s)

#  http://a/b/c/d;p?q
#        g;x?y#s       =  http://a/b/c/g;x?y#s
    url = @base_url.merge('g;x?y#s')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g;x?y#s', url.to_s)
    url = @base_url.route_to('http://a/b/c/g;x?y#s')
    assert_kind_of(URI::Generic, url)
    assert_equal('g;x?y#s', url.to_s)

#  http://a/b/c/d;p?q
#        .             =  http://a/b/c/
    url = @base_url.merge('.')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/', url.to_s)
    url = @base_url.route_to('http://a/b/c/')
    assert_kind_of(URI::Generic, url)
    refute_equal('.', url.to_s) # ok
    assert_equal('./', url.to_s)

#  http://a/b/c/d;p?q
#        ./            =  http://a/b/c/
    url = @base_url.merge('./')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/', url.to_s)
    url = @base_url.route_to('http://a/b/c/')
    assert_kind_of(URI::Generic, url)
    assert_equal('./', url.to_s)

#  http://a/b/c/d;p?q
#        ..            =  http://a/b/
    url = @base_url.merge('..')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/', url.to_s)
    url = @base_url.route_to('http://a/b/')
    assert_kind_of(URI::Generic, url)
    refute_equal('..', url.to_s) # ok
    assert_equal('../', url.to_s)

#  http://a/b/c/d;p?q
#        ../           =  http://a/b/
    url = @base_url.merge('../')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/', url.to_s)
    url = @base_url.route_to('http://a/b/')
    assert_kind_of(URI::Generic, url)
    assert_equal('../', url.to_s)

#  http://a/b/c/d;p?q
#        ../g          =  http://a/b/g
    url = @base_url.merge('../g')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/g', url.to_s)
    url = @base_url.route_to('http://a/b/g')
    assert_kind_of(URI::Generic, url)
    assert_equal('../g', url.to_s)

#  http://a/b/c/d;p?q
#        ../..         =  http://a/
    url = @base_url.merge('../..')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/', url.to_s)
    url = @base_url.route_to('http://a/')
    assert_kind_of(URI::Generic, url)
    refute_equal('../..', url.to_s) # ok
    assert_equal('../../', url.to_s)

#  http://a/b/c/d;p?q
#        ../../        =  http://a/
    url = @base_url.merge('../../')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/', url.to_s)
    url = @base_url.route_to('http://a/')
    assert_kind_of(URI::Generic, url)
    assert_equal('../../', url.to_s)

#  http://a/b/c/d;p?q
#        ../../g       =  http://a/g
    url = @base_url.merge('../../g')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/g', url.to_s)
    url = @base_url.route_to('http://a/g')
    assert_kind_of(URI::Generic, url)
    assert_equal('../../g', url.to_s)

#  http://a/b/c/d;p?q
#        <>            =  (current document)
    url = @base_url.merge('')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/d;p?q', url.to_s)
    url = @base_url.route_to('http://a/b/c/d;p?q')
    assert_kind_of(URI::Generic, url)
    assert_equal('', url.to_s)

#  http://a/b/c/d;p?q
#        /./g          =  http://a/g
    url = @base_url.merge('/./g')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/g', url.to_s)
#    url = @base_url.route_to('http://a/./g')
#    assert_kind_of(URI::Generic, url)
#    assert_equal('/./g', url.to_s)

#  http://a/b/c/d;p?q
#        /../g         =  http://a/g
    url = @base_url.merge('/../g')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/g', url.to_s)
#    url = @base_url.route_to('http://a/../g')
#    assert_kind_of(URI::Generic, url)
#    assert_equal('/../g', url.to_s)

#  http://a/b/c/d;p?q
#        g.            =  http://a/b/c/g.
    url = @base_url.merge('g.')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g.', url.to_s)
    url = @base_url.route_to('http://a/b/c/g.')
    assert_kind_of(URI::Generic, url)
    assert_equal('g.', url.to_s)

#  http://a/b/c/d;p?q
#        .g            =  http://a/b/c/.g
    url = @base_url.merge('.g')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/.g', url.to_s)
    url = @base_url.route_to('http://a/b/c/.g')
    assert_kind_of(URI::Generic, url)
    assert_equal('.g', url.to_s)

#  http://a/b/c/d;p?q
#        g..           =  http://a/b/c/g..
    url = @base_url.merge('g..')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g..', url.to_s)
    url = @base_url.route_to('http://a/b/c/g..')
    assert_kind_of(URI::Generic, url)
    assert_equal('g..', url.to_s)

#  http://a/b/c/d;p?q
#        ..g           =  http://a/b/c/..g
    url = @base_url.merge('..g')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/..g', url.to_s)
    url = @base_url.route_to('http://a/b/c/..g')
    assert_kind_of(URI::Generic, url)
    assert_equal('..g', url.to_s)

#  http://a/b/c/d;p?q
#        ../../../g    =  http://a/g
    url = @base_url.merge('../../../g')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/g', url.to_s)
    url = @base_url.route_to('http://a/g')
    assert_kind_of(URI::Generic, url)
    refute_equal('../../../g', url.to_s)  # ok? yes, it confuses you
    assert_equal('../../g', url.to_s) # and it is clearly

#  http://a/b/c/d;p?q
#        ../../../../g =  http://a/g
    url = @base_url.merge('../../../../g')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/g', url.to_s)
    url = @base_url.route_to('http://a/g')
    assert_kind_of(URI::Generic, url)
    refute_equal('../../../../g', url.to_s) # ok? yes, it confuses you
    assert_equal('../../g', url.to_s)   # and it is clearly

#  http://a/b/c/d;p?q
#        ./../g        =  http://a/b/g
    url = @base_url.merge('./../g')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/g', url.to_s)
    url = @base_url.route_to('http://a/b/g')
    assert_kind_of(URI::Generic, url)
    refute_equal('./../g', url.to_s) # ok
    assert_equal('../g', url.to_s)

#  http://a/b/c/d;p?q
#        ./g/.         =  http://a/b/c/g/
    url = @base_url.merge('./g/.')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g/', url.to_s)
    url = @base_url.route_to('http://a/b/c/g/')
    assert_kind_of(URI::Generic, url)
    refute_equal('./g/.', url.to_s) # ok
    assert_equal('g/', url.to_s)

#  http://a/b/c/d;p?q
#        g/./h         =  http://a/b/c/g/h
    url = @base_url.merge('g/./h')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g/h', url.to_s)
    url = @base_url.route_to('http://a/b/c/g/h')
    assert_kind_of(URI::Generic, url)
    refute_equal('g/./h', url.to_s) # ok
    assert_equal('g/h', url.to_s)

#  http://a/b/c/d;p?q
#        g/../h        =  http://a/b/c/h
    url = @base_url.merge('g/../h')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/h', url.to_s)
    url = @base_url.route_to('http://a/b/c/h')
    assert_kind_of(URI::Generic, url)
    refute_equal('g/../h', url.to_s) # ok
    assert_equal('h', url.to_s)

#  http://a/b/c/d;p?q
#        g;x=1/./y     =  http://a/b/c/g;x=1/y
    url = @base_url.merge('g;x=1/./y')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g;x=1/y', url.to_s)
    url = @base_url.route_to('http://a/b/c/g;x=1/y')
    assert_kind_of(URI::Generic, url)
    refute_equal('g;x=1/./y', url.to_s) # ok
    assert_equal('g;x=1/y', url.to_s)

#  http://a/b/c/d;p?q
#        g;x=1/../y    =  http://a/b/c/y
    url = @base_url.merge('g;x=1/../y')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/y', url.to_s)
    url = @base_url.route_to('http://a/b/c/y')
    assert_kind_of(URI::Generic, url)
    refute_equal('g;x=1/../y', url.to_s) # ok
    assert_equal('y', url.to_s)

#  http://a/b/c/d;p?q
#        g?y/./x       =  http://a/b/c/g?y/./x
    url = @base_url.merge('g?y/./x')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g?y/./x', url.to_s)
    url = @base_url.route_to('http://a/b/c/g?y/./x')
    assert_kind_of(URI::Generic, url)
    assert_equal('g?y/./x', url.to_s)

#  http://a/b/c/d;p?q
#        g?y/../x      =  http://a/b/c/g?y/../x
    url = @base_url.merge('g?y/../x')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g?y/../x', url.to_s)
    url = @base_url.route_to('http://a/b/c/g?y/../x')
    assert_kind_of(URI::Generic, url)
    assert_equal('g?y/../x', url.to_s)

#  http://a/b/c/d;p?q
#        g#s/./x       =  http://a/b/c/g#s/./x
    url = @base_url.merge('g#s/./x')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g#s/./x', url.to_s)
    url = @base_url.route_to('http://a/b/c/g#s/./x')
    assert_kind_of(URI::Generic, url)
    assert_equal('g#s/./x', url.to_s)

#  http://a/b/c/d;p?q
#        g#s/../x      =  http://a/b/c/g#s/../x
    url = @base_url.merge('g#s/../x')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http://a/b/c/g#s/../x', url.to_s)
    url = @base_url.route_to('http://a/b/c/g#s/../x')
    assert_kind_of(URI::Generic, url)
    assert_equal('g#s/../x', url.to_s)

#  http://a/b/c/d;p?q
#        http:g        =  http:g           ; for validating parsers
#                      |  http://a/b/c/g   ; for backwards compatibility
    url = @base_url.merge('http:g')
    assert_kind_of(URI::HTTP, url)
    assert_equal('http:g', url.to_s)
    url = @base_url.route_to('http:g')
    assert_kind_of(URI::Generic, url)
    assert_equal('http:g', url.to_s)
  end

  def test_join
    assert_equal(URI.parse('http://foo/bar'), URI.join('http://foo/bar'))
    assert_equal(URI.parse('http://foo/bar'), URI.join('http://foo', 'bar'))
    assert_equal(URI.parse('http://foo/bar/'), URI.join('http://foo', 'bar/'))

    assert_equal(URI.parse('http://foo/baz'), URI.join('http://foo', 'bar', 'baz'))
    assert_equal(URI.parse('http://foo/baz'), URI.join('http://foo', 'bar', '/baz'))
    assert_equal(URI.parse('http://foo/baz/'), URI.join('http://foo', 'bar', '/baz/'))
    assert_equal(URI.parse('http://foo/bar/baz'), URI.join('http://foo', 'bar/', 'baz'))
    assert_equal(URI.parse('http://foo/hoge'), URI.join('http://foo', 'bar', 'baz', 'hoge'))

    assert_equal(URI.parse('http://foo/bar/baz'), URI.join('http://foo', 'bar/baz'))
    assert_equal(URI.parse('http://foo/bar/hoge'), URI.join('http://foo', 'bar/baz', 'hoge'))
    assert_equal(URI.parse('http://foo/bar/baz/hoge'), URI.join('http://foo', 'bar/baz/', 'hoge'))
    assert_equal(URI.parse('http://foo/hoge'), URI.join('http://foo', 'bar/baz', '/hoge'))
    assert_equal(URI.parse('http://foo/bar/hoge'), URI.join('http://foo', 'bar/baz', 'hoge'))
    assert_equal(URI.parse('http://foo/bar/baz/hoge'), URI.join('http://foo', 'bar/baz/', 'hoge'))
    assert_equal(URI.parse('http://foo/hoge'), URI.join('http://foo', 'bar/baz', '/hoge'))
  end

  # ruby-dev:16728
  def test_set_component
    uri = URI.parse('http://foo:bar@baz')
    assert_equal('oof', uri.user = 'oof')
    assert_equal('http://oof:bar@baz', uri.to_s)
    assert_equal('rab', uri.password = 'rab')
    assert_equal('http://oof:rab@baz', uri.to_s)
    assert_equal('foo', uri.userinfo = 'foo')
    assert_equal('http://foo:rab@baz', uri.to_s)
    assert_equal(['foo', 'bar'], uri.userinfo = ['foo', 'bar'])
    assert_equal('http://foo:bar@baz', uri.to_s)
    assert_equal(['foo'], uri.userinfo = ['foo'])
    assert_equal('http://foo:bar@baz', uri.to_s)
    assert_equal('zab', uri.host = 'zab')
    assert_equal('http://foo:bar@zab', uri.to_s)
    uri.port = ""
    assert_nil(uri.port)
    uri.port = "80"
    assert_equal(80, uri.port)
    uri.port = "080"
    assert_equal(80, uri.port)
    uri.port = " 080 "
    assert_equal(80, uri.port)
    assert_equal(8080, uri.port = 8080)
    assert_equal('http://foo:bar@zab:8080', uri.to_s)
    assert_equal('/', uri.path = '/')
    assert_equal('http://foo:bar@zab:8080/', uri.to_s)
    assert_equal('a=1', uri.query = 'a=1')
    assert_equal('http://foo:bar@zab:8080/?a=1', uri.to_s)
    assert_equal('b123', uri.fragment = 'b123')
    assert_equal('http://foo:bar@zab:8080/?a=1#b123', uri.to_s)
    assert_equal('a[]=1', uri.query = 'a[]=1')
    assert_equal('http://foo:bar@zab:8080/?a[]=1#b123', uri.to_s)
    uri = URI.parse('http://foo:bar@zab:8080/?a[]=1#b123')
    assert_equal('http://foo:bar@zab:8080/?a[]=1#b123', uri.to_s)

    uri = URI.parse('http://example.com')
    assert_raise(URI::InvalidURIError) { uri.password = 'bar' }
    assert_equal("foo\nbar", uri.query = "foo\nbar")
    uri.userinfo = 'foo:bar'
    assert_equal('http://foo:bar@example.com?foobar', uri.to_s)
    assert_raise(URI::InvalidURIError) { uri.registry = 'bar' }
    assert_raise(URI::InvalidURIError) { uri.opaque = 'bar' }

    uri = URI.parse('mailto:foo@example.com')
    assert_raise(URI::InvalidURIError) { uri.user = 'bar' }
    assert_raise(URI::InvalidURIError) { uri.password = 'bar' }
    assert_raise(URI::InvalidURIError) { uri.userinfo = ['bar', 'baz'] }
    assert_raise(URI::InvalidURIError) { uri.host = 'bar' }
    assert_raise(URI::InvalidURIError) { uri.port = 'bar' }
    assert_raise(URI::InvalidURIError) { uri.path = 'bar' }
    assert_raise(URI::InvalidURIError) { uri.query = 'bar' }

    uri = URI.parse('foo:bar')
    assert_raise(URI::InvalidComponentError) { uri.opaque = '/baz' }
    uri.opaque = 'xyzzy'
    assert_equal('foo:xyzzy', uri.to_s)
  end

  def test_bad_password_component
    uri = URI.parse('http://foo:bar@baz')
    password = 'foo@bar'
    e = assert_raise(URI::InvalidComponentError) do
      uri.password = password
    end
    refute_match Regexp.new(password), e.message
  end

  def test_set_scheme
    uri = URI.parse 'HTTP://example'

    assert_equal 'http://example', uri.to_s
  end

  def test_hierarchical
    hierarchical = URI.parse('http://a.b.c/example')
    opaque = URI.parse('mailto:mduerst@ifi.unizh.ch')

    assert_predicate hierarchical, :hierarchical?
    refute_predicate opaque, :hierarchical?
  end

  def test_absolute
    abs_uri = URI.parse('http://a.b.c/')
    not_abs = URI.parse('a.b.c')

    refute_predicate not_abs, :absolute?

    assert_predicate abs_uri, :absolute
    assert_predicate abs_uri, :absolute?
  end

  def test_ipv6
    assert_equal("[::1]", URI("http://[::1]/bar/baz").host)
    assert_equal("::1", URI("http://[::1]/bar/baz").hostname)

    u = URI("http://foo/bar")
    assert_equal("http://foo/bar", u.to_s)
    u.hostname = "[::1]"
    assert_equal("http://[::1]/bar", u.to_s)
    u.hostname = "::1"
    assert_equal("http://[::1]/bar", u.to_s)
    u.hostname = ""
    assert_equal("http:///bar", u.to_s)
  end

  def test_build
    u = URI::Generic.build(['http', nil, 'example.com', 80, nil, '/foo', nil, nil, nil])
    assert_equal('http://example.com:80/foo', u.to_s)
    assert_equal(Encoding::UTF_8, u.to_s.encoding)

    u = URI::Generic.build(:port => "5432")
    assert_equal(":5432", u.to_s)
    assert_equal(5432, u.port)

    u = URI::Generic.build(:scheme => "http", :host => "::1", :path => "/bar/baz")
    assert_equal("http://[::1]/bar/baz", u.to_s)
    assert_equal("[::1]", u.host)
    assert_equal("::1", u.hostname)

    u = URI::Generic.build(:scheme => "http", :host => "[::1]", :path => "/bar/baz")
    assert_equal("http://[::1]/bar/baz", u.to_s)
    assert_equal("[::1]", u.host)
    assert_equal("::1", u.hostname)
  end

  def test_build2
    u = URI::Generic.build2(path: "/foo bar/baz")
    assert_equal('/foo%20bar/baz', u.to_s)

    u = URI::Generic.build2(['http', nil, 'example.com', 80, nil, '/foo bar' , nil, nil, nil])
    assert_equal('http://example.com:80/foo%20bar', u.to_s)
  end

  # 192.0.2.0/24 is TEST-NET.  [RFC3330]

  def test_find_proxy_bad_uri
    assert_raise(URI::BadURIError){ URI("foo").find_proxy }
  end

  def test_find_proxy_no_env
    with_proxy_env({}) {|env|
      assert_nil(URI("http://192.0.2.1/").find_proxy(env))
      assert_nil(URI("ftp://192.0.2.1/").find_proxy(env))
    }
  end

  def test_find_proxy
    with_proxy_env('http_proxy'=>'http://127.0.0.1:8080') {|env|
      assert_equal(URI('http://127.0.0.1:8080'), URI("http://192.0.2.1/").find_proxy(env))
      assert_nil(URI("ftp://192.0.2.1/").find_proxy(env))
    }
    with_proxy_env('ftp_proxy'=>'http://127.0.0.1:8080') {|env|
      assert_nil(URI("http://192.0.2.1/").find_proxy(env))
      assert_equal(URI('http://127.0.0.1:8080'), URI("ftp://192.0.2.1/").find_proxy(env))
    }
  end

  def test_find_proxy_get
    with_proxy_env('REQUEST_METHOD'=>'GET') {|env|
      assert_nil(URI("http://192.0.2.1/").find_proxy(env))
    }
    with_proxy_env('CGI_HTTP_PROXY'=>'http://127.0.0.1:8080', 'REQUEST_METHOD'=>'GET') {|env|
      assert_equal(URI('http://127.0.0.1:8080'), URI("http://192.0.2.1/").find_proxy(env))
    }
  end

  def test_find_proxy_no_proxy
    getaddress = IPSocket.method(:getaddress)
    example_address = nil
    IPSocket.singleton_class.class_eval do
      undef getaddress
      define_method(:getaddress) do |host|
        case host
        when "example.org", "www.example.org"
          example_address
        when /\A\d+(?:\.\d+){3}\z/
          host
        else
          raise host
        end
      end
    end

    with_proxy_env('http_proxy'=>'http://127.0.0.1:8080', 'no_proxy'=>'192.0.2.2') {|env|
      assert_equal(URI('http://127.0.0.1:8080'), URI("http://192.0.2.1/").find_proxy(env))
      assert_nil(URI("http://192.0.2.2/").find_proxy(env))

      example_address = "192.0.2.1"
      assert_equal(URI('http://127.0.0.1:8080'), URI.parse("http://example.org").find_proxy(env))
      example_address = "192.0.2.2"
      assert_nil(URI.parse("http://example.org").find_proxy(env))
    }
    with_proxy_env('http_proxy'=>'http://127.0.0.1:8080', 'no_proxy'=>'example.org') {|env|
      assert_nil(URI("http://example.org/").find_proxy(env))
      assert_nil(URI("http://www.example.org/").find_proxy(env))
    }
    with_proxy_env('http_proxy'=>'http://127.0.0.1:8080', 'no_proxy'=>'.example.org') {|env|
      assert_equal(URI('http://127.0.0.1:8080'), URI("http://example.org/").find_proxy(env))
      assert_nil(URI("http://www.example.org/").find_proxy(env))
    }
  ensure
    IPSocket.singleton_class.class_eval do
      undef getaddress
      define_method(:getaddress, getaddress)
    end
  end

  def test_find_proxy_no_proxy_cidr
    with_proxy_env('http_proxy'=>'http://127.0.0.1:8080', 'no_proxy'=>'192.0.2.0/24') {|env|
      assert_equal(URI('http://127.0.0.1:8080'), URI("http://192.0.1.1/").find_proxy(env))
      assert_nil(URI("http://192.0.2.1/").find_proxy(env))
      assert_nil(URI("http://192.0.2.2/").find_proxy(env))
    }
  end

  def test_find_proxy_bad_value
    with_proxy_env('http_proxy'=>'') {|env|
      assert_nil(URI("http://192.0.2.1/").find_proxy(env))
      assert_nil(URI("ftp://192.0.2.1/").find_proxy(env))
    }
    with_proxy_env('ftp_proxy'=>'') {|env|
      assert_nil(URI("http://192.0.2.1/").find_proxy(env))
      assert_nil(URI("ftp://192.0.2.1/").find_proxy(env))
    }
  end

  def test_find_proxy_case_sensitive_env
    with_proxy_env_case_sensitive('http_proxy'=>'http://127.0.0.1:8080', 'REQUEST_METHOD'=>'GET') {|env|
      assert_equal(URI('http://127.0.0.1:8080'), URI("http://192.0.2.1/").find_proxy(env))
    }
    with_proxy_env_case_sensitive('HTTP_PROXY'=>'http://127.0.0.1:8081', 'REQUEST_METHOD'=>'GET') {|env|
      assert_nil(URI("http://192.0.2.1/").find_proxy(env))
    }
    with_proxy_env_case_sensitive('http_proxy'=>'http://127.0.0.1:8080', 'HTTP_PROXY'=>'http://127.0.0.1:8081', 'REQUEST_METHOD'=>'GET') {|env|
      assert_equal(URI('http://127.0.0.1:8080'), URI("http://192.0.2.1/").find_proxy(env))
    }
  end

  def test_use_proxy_p
    [
      ['example.com', nil, 80, '', true],
      ['example.com', nil, 80, 'example.com:80', false],
      ['example.com', nil, 80, 'example.org,example.com:80,example.net', false],
      ['foo.example.com', nil, 80, 'example.com', false],
      ['foo.example.com', nil, 80, '.example.com', false],
      ['example.com', nil, 80, '.example.com', true],
      ['xample.com', nil, 80, '.example.com', true],
      ['fooexample.com', nil, 80, '.example.com', true],
      ['foo.example.com', nil, 80, 'example.com:80', false],
      ['foo.eXample.com', nil, 80, 'example.com:80', false],
      ['foo.example.com', nil, 80, 'eXample.com:80', false],
      ['foo.example.com', nil, 80, 'example.com:443', true],
      ['127.0.0.1', '127.0.0.1', 80, '10.224.0.0/22', true],
      ['10.224.1.1', '10.224.1.1', 80, '10.224.1.1', false],
      ['10.224.1.1', '10.224.1.1', 80, '10.224.0.0/22', false],
    ].each do |hostname, addr, port, no_proxy, expected|
      assert_equal expected, URI::Generic.use_proxy?(hostname, addr, port, no_proxy),
        "use_proxy?('#{hostname}', '#{addr}', #{port}, '#{no_proxy}')"
    end
  end

  def test_split
    assert_equal [nil, nil, nil, nil, nil, "", nil, nil, nil], URI.split("//")
  end

  class CaseInsensitiveEnv
    def initialize(h={})
      @h = {}
      h.each {|k, v| self[k] = v }
    end

    def []=(k, v)
      if v
        @h[k.downcase] = [k, v.to_s]
      else
        @h.delete [k.downcase]
      end
      v
    end

    def [](k)
      k = k.downcase
      @h.has_key?(k) ? @h[k][1] : nil
    end

    def length
      @h.length
    end

    def include?(k)
      @h.include? k.downcase
    end

    def shift
      return nil if @h.empty?
      _kd, (k, v) = @h.shift
      [k, v]
    end

    def each
      @h.each {|kd, (k, v)| yield [k, v] }
    end

    def reject
      ret = CaseInsensitiveEnv.new
      self.each {|k, v|
        ret[k] = v unless yield [k, v]
      }
      ret
    end

    def to_hash
      ret = {}
      self.each {|k, v|
        ret[k] = v
      }
      ret
    end
  end

  def with_proxy_real_env(h)
    h = h.dup
    ['http', 'https', 'ftp'].each do |scheme|
      name = "#{scheme}_proxy"
      h[name] ||= nil
      h["CGI_#{name.upcase}"] ||= nil
    end
    begin
      old = {}
      h.each_key {|k| old[k] = ENV[k] }
      h.each {|k, v| ENV[k] = v }
      yield ENV
    ensure
      h.each_key {|k| ENV[k] = old[k] }
    end
    h.reject! {|k, v| v.nil? }
  end

  def with_proxy_env(h, &b)
    with_proxy_real_env(h, &b)
    h = h.reject {|k, v| v.nil? }
    yield h
    yield CaseInsensitiveEnv.new(h)
  end

  def with_proxy_env_case_sensitive(h, &b)
    with_proxy_real_env(h, &b) unless RUBY_PLATFORM =~ /mswin|mingw/
    h = h.reject {|k, v| v.nil? }
    yield h
  end

end
