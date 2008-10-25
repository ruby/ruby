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
    @a2 = quick_gem 'a', '2'

    @server = Gem::Server.new Gem.dir, process_based_port, false
    @req = WEBrick::HTTPRequest.new :Logger => nil
    @res = WEBrick::HTTPResponse.new :HTTPVersion => '1.0'
  end

  def test_Marshal
    data = StringIO.new "GET /Marshal.#{Gem.marshal_version} HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.Marshal @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'application/octet-stream', @res['content-type']

    si = Gem::SourceIndex.new
    si.add_specs @a1, @a2

    assert_equal si, Marshal.load(@res.body)
  end

  def test_Marshal_Z
    data = StringIO.new "GET /Marshal.#{Gem.marshal_version}.Z HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.Marshal @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'application/x-deflate', @res['content-type']

    si = Gem::SourceIndex.new
    si.add_specs @a1, @a2

    assert_equal si, Marshal.load(Gem.inflate(@res.body))
  end

  def test_latest_specs
    data = StringIO.new "GET /latest_specs.#{Gem.marshal_version} HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.latest_specs @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'application/octet-stream', @res['content-type']
    assert_equal [['a', Gem::Version.new(2), Gem::Platform::RUBY]],
                 Marshal.load(@res.body)
  end

  def test_latest_specs_gz
    data = StringIO.new "GET /latest_specs.#{Gem.marshal_version}.gz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.latest_specs @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'application/x-gzip', @res['content-type']
    assert_equal [['a', Gem::Version.new(2), Gem::Platform::RUBY]],
                 Marshal.load(Gem.gunzip(@res.body))
  end

  def test_quick_a_1_gemspec_rz
    data = StringIO.new "GET /quick/a-1.gemspec.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 200, @res.status, @res.body
    assert @res['date']
    assert_equal 'application/x-deflate', @res['content-type']

    spec = YAML.load Gem.inflate(@res.body)
    assert_equal 'a', spec.name
    assert_equal Gem::Version.new(1), spec.version
  end

  def test_quick_a_1_mswin32_gemspec_rz
    a1_p = quick_gem 'a', '1' do |s| s.platform = Gem::Platform.local end

    data = StringIO.new "GET /quick/a-1-#{Gem::Platform.local}.gemspec.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 200, @res.status, @res.body
    assert @res['date']
    assert_equal 'application/x-deflate', @res['content-type']

    spec = YAML.load Gem.inflate(@res.body)
    assert_equal 'a', spec.name
    assert_equal Gem::Version.new(1), spec.version
    assert_equal Gem::Platform.local, spec.platform
  end

  def test_quick_common_substrings
    ab1 = quick_gem 'ab', '1'

    data = StringIO.new "GET /quick/a-1.gemspec.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 200, @res.status, @res.body
    assert @res['date']
    assert_equal 'application/x-deflate', @res['content-type']

    spec = YAML.load Gem.inflate(@res.body)
    assert_equal 'a', spec.name
    assert_equal Gem::Version.new(1), spec.version
  end

  def test_quick_index
    data = StringIO.new "GET /quick/index HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'text/plain', @res['content-type']
    assert_equal "a-1\na-2", @res.body
  end

  def test_quick_index_rz
    data = StringIO.new "GET /quick/index.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'application/x-deflate', @res['content-type']
    assert_equal "a-1\na-2", Gem.inflate(@res.body)
  end

  def test_quick_latest_index
    data = StringIO.new "GET /quick/latest_index HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'text/plain', @res['content-type']
    assert_equal 'a-2', @res.body
  end

  def test_quick_latest_index_rz
    data = StringIO.new "GET /quick/latest_index.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'application/x-deflate', @res['content-type']
    assert_equal 'a-2', Gem.inflate(@res.body)
  end

  def test_quick_missing
    data = StringIO.new "GET /quick/z-9.gemspec.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 404, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'text/plain', @res['content-type']
    assert_equal 'No gems found matching "z" "9" nil', @res.body
    assert_equal 404, @res.status
  end

  def test_quick_marshal_a_1_gemspec_rz
    data = StringIO.new "GET /quick/Marshal.#{Gem.marshal_version}/a-1.gemspec.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 200, @res.status, @res.body
    assert @res['date']
    assert_equal 'application/x-deflate', @res['content-type']

    spec = Marshal.load Gem.inflate(@res.body)
    assert_equal 'a', spec.name
    assert_equal Gem::Version.new(1), spec.version
  end

  def test_quick_marshal_a_1_mswin32_gemspec_rz
    a1_p = quick_gem 'a', '1' do |s| s.platform = Gem::Platform.local end

    data = StringIO.new "GET /quick/Marshal.#{Gem.marshal_version}/a-1-#{Gem::Platform.local}.gemspec.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 200, @res.status, @res.body
    assert @res['date']
    assert_equal 'application/x-deflate', @res['content-type']

    spec = Marshal.load Gem.inflate(@res.body)
    assert_equal 'a', spec.name
    assert_equal Gem::Version.new(1), spec.version
    assert_equal Gem::Platform.local, spec.platform
  end


  def test_root
    data = StringIO.new "GET / HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.root @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'text/html', @res['content-type']
  end

  def test_specs
    data = StringIO.new "GET /specs.#{Gem.marshal_version} HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.specs @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'application/octet-stream', @res['content-type']

    assert_equal [['a', Gem::Version.new(1), Gem::Platform::RUBY],
                  ['a', Gem::Version.new(2), Gem::Platform::RUBY]],
                 Marshal.load(@res.body)
  end

  def test_specs_gz
    data = StringIO.new "GET /specs.#{Gem.marshal_version}.gz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.specs @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'application/x-gzip', @res['content-type']

    assert_equal [['a', Gem::Version.new(1), Gem::Platform::RUBY],
                  ['a', Gem::Version.new(2), Gem::Platform::RUBY]],
                 Marshal.load(Gem.gunzip(@res.body))
  end

  def test_yaml
    data = StringIO.new "GET /yaml.#{Gem.marshal_version} HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.yaml @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'text/plain', @res['content-type']

    si = Gem::SourceIndex.new
    si.add_specs @a1, @a2

    assert_equal si, YAML.load(@res.body)
  end

  def test_yaml_Z
    data = StringIO.new "GET /yaml.#{Gem.marshal_version}.Z HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.yaml @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'application/x-deflate', @res['content-type']

    si = Gem::SourceIndex.new
    si.add_specs @a1, @a2

    assert_equal si, YAML.load(Gem.inflate(@res.body))
  end

end

