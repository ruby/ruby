require 'test/unit'
require 'uri/ftp'

module URI


class TestFTP < Test::Unit::TestCase
  def setup
  end

  def test_parse
    url = URI.parse('ftp://user:pass@host.com/abc/def')
    assert_kind_of(URI::FTP, url)

    exp = [
      'ftp',
      'user:pass', 'host.com', URI::FTP.default_port, 
      '/abc/def', nil,
    ]
    ary = [
      url.scheme, url.userinfo, url.host, url.port,
      url.path, url.opaque
    ]
    assert_equal(exp, ary)

    assert_equal('user', url.user)
    assert_equal('pass', url.password)
  end

  def test_select
    assert_equal(['ftp', 'a.b.c', 21], URI.parse('ftp://a.b.c/').select(:scheme, :host, :port))
    u = URI.parse('ftp://a.b.c/')
    ary = u.component.collect {|c| u.send(c)}
    assert_equal(ary, u.select(*u.component))
    assert_raises(ArgumentError) do
      u.select(:scheme, :host, :not_exist, :port)
    end
  end
end


end
