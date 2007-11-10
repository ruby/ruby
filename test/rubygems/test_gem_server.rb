require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/server'
require 'stringio'

class Gem::Server
  attr_reader :server
end

class TestGemServer < RubyGemTestCase

  def setup
    super

    @a1 = quick_gem 'a', '1'

    @server = Gem::Server.new Gem.dir, 8809, false
    @req = WEBrick::HTTPRequest.new :Logger => nil
    @res = WEBrick::HTTPResponse.new :HTTPVersion => '1.0'
  end

  def test_quick_index
    data = StringIO.new "GET /quick/index HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'text/plain', @res['content-type']
    assert_equal "a-1", @res.body
  end

  def test_quick_index_rz
    data = StringIO.new "GET /quick/index.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'text/plain', @res['content-type']
    assert_equal "a-1", Zlib::Inflate.inflate(@res.body)
  end

  def test_quick_a_1_gemspec_rz
    data = StringIO.new "GET /quick/a-1.gemspec.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert @res['date']
    assert_equal 'text/plain', @res['content-type']
    yaml = Zlib::Inflate.inflate(@res.body)
    assert_match %r|Gem::Specification|, yaml
    assert_match %r|name: a|, yaml
    assert_match %r|version: "1"|, yaml
  end

  def test_quick_z_9_gemspec_rz
    data = StringIO.new "GET /quick/z-9.gemspec.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'text/plain', @res['content-type']
    assert_equal '', @res.body
    assert_equal 404, @res.status
  end

end

