require 'runit/testcase'
require 'runit/cui/testrunner'
require 'uri/http'
module URI
  class Generic
    def to_ary
      component_ary
    end
  end
end

class TestHTTP < RUNIT::TestCase
  def setup
  end

  def teardown
  end

  def test_parse
    u = URI.parse('http://a')
    assert_kind_of(URI::HTTP, u)
    assert_equal(['http', 
		   nil, 'a', URI::HTTP.default_port,
		   '', nil, nil], u.to_ary)
  end

  def test_normalize
    host = 'aBcD'
    u1 = URI.parse('http://' + host          + '/eFg?HiJ')
    u2 = URI.parse('http://' + host.downcase + '/eFg?HiJ')
    assert(u1.normalize.host == 'abcd')
    assert(u1.normalize.path == u1.path)
    assert(u1.normalize == u2.normalize)
    assert(!u1.normalize.host.equal?(u1.host))
    assert( u2.normalize.host.equal?(u2.host))

    assert_equal('http://abc/', URI.parse('http://abc').normalize.to_s)
  end

  def test_equal
    assert(URI.parse('http://abc') == URI.parse('http://ABC'))
    assert(URI.parse('http://abc/def') == URI.parse('http://ABC/def'))
    assert(URI.parse('http://abc/def') != URI.parse('http://ABC/DEF'))
  end

  def test_request_uri
    assert_equal('/',         URI.parse('http://a.b.c/').request_uri)
    assert_equal('/?abc=def', URI.parse('http://a.b.c/?abc=def').request_uri)
    assert_equal('/',         URI.parse('http://a.b.c').request_uri)
    assert_equal('/?abc=def', URI.parse('http://a.b.c?abc=def').request_uri)
  end

  def test_select
    assert_equal(['http', 'a.b.c', 80], URI.parse('http://a.b.c/').select(:scheme, :host, :port))
    u = URI.parse('http://a.b.c/')
    assert_equal(u.to_ary, u.select(*u.component))
    assert_exception(ArgumentError) do
      u.select(:scheme, :host, :not_exist, :port)
    end
  end
end

if $0 == __FILE__
  if ARGV.size == 0
    suite = TestHTTP.suite
  else
    suite = RUNIT::TestSuite.new
    ARGV.each do |testmethod|
      suite.add_test(TestHTTP.new(testmethod))
    end
  end
  RUNIT::CUI::TestRunner.run(suite)
end
