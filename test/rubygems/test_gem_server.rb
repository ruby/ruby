require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/server'
require 'stringio'

class Gem::Server
  attr_accessor :source_index
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

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'text/plain', @res['content-type']
    assert_equal "a-1", @res.body
  end

  def test_quick_index_rz
    data = StringIO.new "GET /quick/index.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'text/plain', @res['content-type']
    assert_equal "a-1", Zlib::Inflate.inflate(@res.body)
  end

  def test_quick_a_1_gemspec_rz
    data = StringIO.new "GET /quick/a-1.gemspec.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 200, @res.status, @res.body
    assert @res['date']
    assert_equal 'text/plain', @res['content-type']
    yaml = Zlib::Inflate.inflate(@res.body)
    assert_match %r|Gem::Specification|, yaml
    assert_match %r|name: a|, yaml
    assert_match %r|version: "1"|, yaml
  end

  def test_quick_a_1_mswin32_gemspec_rz
    a1_p = quick_gem 'a', '1' do |s| s.platform = Gem::Platform.local end
    si = Gem::SourceIndex.new @a1.full_name => @a1, a1_p.full_name => a1_p
    @server.source_index = si

    data = StringIO.new "GET /quick/a-1-#{Gem::Platform.local}.gemspec.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 200, @res.status, @res.body
    assert @res['date']
    assert_equal 'text/plain', @res['content-type']
    yaml = Zlib::Inflate.inflate(@res.body)
    assert_match %r|Gem::Specification|, yaml
    assert_match %r|name: a|, yaml
    assert_match %r|version: "1"|, yaml
  end

  def test_quick_common_substrings
    ab1 = quick_gem 'ab', '1'
    si = Gem::SourceIndex.new @a1.full_name => @a1, ab1.full_name => ab1
    @server.source_index = si

    data = StringIO.new "GET /quick/a-1.gemspec.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 200, @res.status, @res.body
    assert @res['date']
    assert_equal 'text/plain', @res['content-type']
    yaml = Zlib::Inflate.inflate @res.body
    assert_match %r|Gem::Specification|, yaml
    assert_match %r|name: a$|, yaml
    assert_match %r|version: "1"|, yaml
  end

  def test_quick_z_9_gemspec_rz
    data = StringIO.new "GET /quick/z-9.gemspec.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 404, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'text/plain', @res['content-type']
    assert_equal 'No gems found matching "z" "9" nil', @res.body
    assert_equal 404, @res.status
  end

end

