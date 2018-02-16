# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/server'
require 'stringio'

class Gem::Server
  attr_reader :server
end

class TestGemServer < Gem::TestCase
  def process_based_port
    0
  end

  def setup
    super

    @a1   = quick_gem 'a', '1'
    @a2   = quick_gem 'a', '2'
    @a3_p = quick_gem 'a', '3.a'

    @server = Gem::Server.new Gem.dir, process_based_port, false
    @req = WEBrick::HTTPRequest.new :Logger => nil
    @res = WEBrick::HTTPResponse.new :HTTPVersion => '1.0'
  end

  def test_doc_root_3
    orig_rdoc_version = Gem::RDoc.rdoc_version
    Gem::RDoc.instance_variable_set :@rdoc_version, Gem::Version.new('3.12')

    assert_equal '/doc_root/X-1/rdoc/index.html', @server.doc_root('X-1')

  ensure
    Gem::RDoc.instance_variable_set :@rdoc_version, orig_rdoc_version
  end

  def test_doc_root_4
    orig_rdoc_version = Gem::RDoc.rdoc_version
    Gem::RDoc.instance_variable_set :@rdoc_version, Gem::Version.new('4.0')

    assert_equal '/doc_root/X-1/', @server.doc_root('X-1')

  ensure
    Gem::RDoc.instance_variable_set :@rdoc_version, orig_rdoc_version
  end

  def test_have_rdoc_4_plus_eh
    orig_rdoc_version = Gem::RDoc.rdoc_version
    Gem::RDoc.instance_variable_set(:@rdoc_version, Gem::Version.new('4.0'))

    server = Gem::Server.new Gem.dir, 0, false
    assert server.have_rdoc_4_plus?

    Gem::RDoc.instance_variable_set :@rdoc_version, Gem::Version.new('3.12')

    server = Gem::Server.new Gem.dir, 0, false
    refute server.have_rdoc_4_plus?

    Gem::RDoc.instance_variable_set(:@rdoc_version,
                                    Gem::Version.new('4.0.0.preview2'))

    server = Gem::Server.new Gem.dir, 0, false
    assert server.have_rdoc_4_plus?
  ensure
    Gem::RDoc.instance_variable_set :@rdoc_version, orig_rdoc_version
  end

  def test_spec_dirs
    s = Gem::Server.new Gem.dir, process_based_port, false

    assert_equal [File.join(Gem.dir, 'specifications')], s.spec_dirs

    s = Gem::Server.new [Gem.dir, Gem.dir], process_based_port, false

    assert_equal [File.join(Gem.dir, 'specifications'),
                  File.join(Gem.dir, 'specifications')], s.spec_dirs
  end

  def test_latest_specs
    data = StringIO.new "GET /latest_specs.#{Gem.marshal_version} HTTP/1.0\r\n\r\n"
    @req.parse data

    Gem::Deprecate.skip_during do
      @server.latest_specs @req, @res
    end

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'application/octet-stream', @res['content-type']
    assert_equal [['a', Gem::Version.new(2), Gem::Platform::RUBY]],
    Marshal.load(@res.body)
  end

  def test_latest_specs_gemdirs
    data = StringIO.new "GET /latest_specs.#{Gem.marshal_version} HTTP/1.0\r\n\r\n"
    dir = "#{@gemhome}2"

    spec = util_spec 'z', 9

    specs_dir = File.join dir, 'specifications'
    FileUtils.mkdir_p specs_dir

    open File.join(specs_dir, spec.spec_name), 'w' do |io|
      io.write spec.to_ruby
    end

    server = Gem::Server.new dir, process_based_port, false

    @req.parse data

    server.latest_specs @req, @res

    assert_equal 200, @res.status

    assert_equal [['z', v(9), Gem::Platform::RUBY]], Marshal.load(@res.body)
  end

  def test_latest_specs_gz
    data = StringIO.new "GET /latest_specs.#{Gem.marshal_version}.gz HTTP/1.0\r\n\r\n"
    @req.parse data

    Gem::Deprecate.skip_during do
      @server.latest_specs @req, @res
    end

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'application/x-gzip', @res['content-type']
    assert_equal [['a', Gem::Version.new(2), Gem::Platform::RUBY]],
                 Marshal.load(Gem.gunzip(@res.body))
  end

  def test_listen
    util_listen

    capture_io do
      @server.listen
    end

    assert_equal 1, @server.server.listeners.length
  end

  def test_listen_addresses
    util_listen

    capture_io do
      @server.listen %w[a b]
    end

    assert_equal 2, @server.server.listeners.length
  end

  def test_prerelease_specs
    data = StringIO.new "GET /prerelease_specs.#{Gem.marshal_version} HTTP/1.0\r\n\r\n"
    @req.parse data

    Gem::Deprecate.skip_during do
      @server.prerelease_specs @req, @res
    end

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'application/octet-stream', @res['content-type']
    assert_equal [['a', v('3.a'), Gem::Platform::RUBY]],
                 Marshal.load(@res.body)
  end

  def test_prerelease_specs_gz
    data = StringIO.new "GET /prerelease_specs.#{Gem.marshal_version}.gz HTTP/1.0\r\n\r\n"
    @req.parse data

    Gem::Deprecate.skip_during do
      @server.prerelease_specs @req, @res
    end

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'application/x-gzip', @res['content-type']
    assert_equal [['a', v('3.a'), Gem::Platform::RUBY]],
                 Marshal.load(Gem.gunzip(@res.body))
  end

  def test_quick_gemdirs
    data = StringIO.new "GET /quick/Marshal.4.8/z-9.gemspec.rz HTTP/1.0\r\n\r\n"
    dir = "#{@gemhome}2"

    server = Gem::Server.new dir, process_based_port, false

    @req.parse data

    server.quick @req, @res

    assert_equal 404, @res.status

    spec = util_spec 'z', 9

    specs_dir = File.join dir, 'specifications'

    FileUtils.mkdir_p specs_dir

    open File.join(specs_dir, spec.spec_name), 'w' do |io|
      io.write spec.to_ruby
    end

    data.rewind

    req = WEBrick::HTTPRequest.new :Logger => nil
    res = WEBrick::HTTPResponse.new :HTTPVersion => '1.0'
    req.parse data

    server.quick req, res

    assert_equal 200, res.status
  end

  def test_quick_missing
    data = StringIO.new "GET /quick/Marshal.4.8/z-9.gemspec.rz HTTP/1.0\r\n\r\n"
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
    quick_gem 'a', '1' do |s| s.platform = Gem::Platform.local end

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

  def test_quick_marshal_a_3_a_gemspec_rz
    data = StringIO.new "GET /quick/Marshal.#{Gem.marshal_version}/a-3.a.gemspec.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 200, @res.status, @res.body
    assert @res['date']
    assert_equal 'application/x-deflate', @res['content-type']

    spec = Marshal.load Gem.inflate(@res.body)
    assert_equal 'a', spec.name
    assert_equal v('3.a'), spec.version
  end

  def test_quick_marshal_a_b_3_a_gemspec_rz
    quick_gem 'a-b', '3.a'

    data = StringIO.new "GET /quick/Marshal.#{Gem.marshal_version}/a-b-3.a.gemspec.rz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.quick @req, @res

    assert_equal 200, @res.status, @res.body
    assert @res['date']
    assert_equal 'application/x-deflate', @res['content-type']

    spec = Marshal.load Gem.inflate(@res.body)
    assert_equal 'a-b', spec.name
    assert_equal v('3.a'), spec.version
  end

  def test_rdoc
    data = StringIO.new "GET /rdoc?q=a HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.rdoc @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r|No documentation found|, @res.body
    assert_equal 'text/html', @res['content-type']
  end

  def test_root
    data = StringIO.new "GET / HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.root @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'text/html', @res['content-type']
  end

  def test_root_gemdirs
    data = StringIO.new "GET / HTTP/1.0\r\n\r\n"
    dir = "#{@gemhome}2"

    spec = util_spec 'z', 9

    specs_dir = File.join dir, 'specifications'
    FileUtils.mkdir_p specs_dir

    open File.join(specs_dir, spec.spec_name), 'w' do |io|
      io.write spec.to_ruby
    end

    server = Gem::Server.new dir, process_based_port, false

    @req.parse data

    server.root @req, @res

    assert_equal 200, @res.status
    assert_match 'z 9', @res.body
  end


  def test_xss_homepage_fix_289313
    data = StringIO.new "GET / HTTP/1.0\r\n\r\n"
    dir = "#{@gemhome}2"

    spec = util_spec 'xsshomepagegem', 1
    spec.homepage = "javascript:confirm(document.domain)"

    specs_dir = File.join dir, 'specifications'
    FileUtils.mkdir_p specs_dir

    open File.join(specs_dir, spec.spec_name), 'w' do |io|
      io.write spec.to_ruby
    end

    server = Gem::Server.new dir, process_based_port, false

    @req.parse data

    server.root @req, @res

    assert_equal 200, @res.status
    assert_match 'xsshomepagegem 1', @res.body

    # This verifies that the homepage for this spec is not displayed and is set to ".", because it's not a 
    # valid HTTP/HTTPS URL and could be unsafe in an HTML context.  We would prefer to throw an exception here,
    # but spec.homepage is currently free form and not currently required to be a URL, this behavior may be 
    # validated in future versions of Gem::Specification.
    #
    # There are two variant we're checking here, one where rdoc is not present, and one where rdoc is present in the same regex:
    #
    # Variant #1 - rdoc not installed
    #
    #   <b>xsshomepagegem 1</b>
    #
    #
    #  <span title="rdoc not installed">[rdoc]</span>
    #
    #
    #
    #  <a href="." title=".">[www]</a>
    #
    # Variant #2 - rdoc installed
    #
    #   <b>xsshomepagegem 1</b>
    #
    #
    #  <a href="\/doc_root\/xsshomepagegem-1\/">\[rdoc\]<\/a>
    #
    #
    #
    #  <a href="." title=".">[www]</a>
    regex_match = /xsshomepagegem 1<\/b>[\s]+(<span title="rdoc not installed">\[rdoc\]<\/span>|<a href="\/doc_root\/xsshomepagegem-1\/">\[rdoc\]<\/a>)[\s]+<a href="\." title="\.">\[www\]<\/a>/
    assert_match regex_match, @res.body
  end

  def test_invalid_homepage
    data = StringIO.new "GET / HTTP/1.0\r\n\r\n"
    dir = "#{@gemhome}2"

    spec = util_spec 'invalidhomepagegem', 1
    spec.homepage = "notavalidhomepageurl"

    specs_dir = File.join dir, 'specifications'
    FileUtils.mkdir_p specs_dir

    open File.join(specs_dir, spec.spec_name), 'w' do |io|
      io.write spec.to_ruby
    end

    server = Gem::Server.new dir, process_based_port, false

    @req.parse data

    server.root @req, @res

    assert_equal 200, @res.status
    assert_match 'invalidhomepagegem 1', @res.body

    # This verifies that the homepage for this spec is not displayed and is set to ".", because it's not a 
    # valid HTTP/HTTPS URL and could be unsafe in an HTML context.  We would prefer to throw an exception here,
    # but spec.homepage is currently free form and not currently required to be a URL, this behavior may be 
    # validated in future versions of Gem::Specification.
    #
    # There are two variant we're checking here, one where rdoc is not present, and one where rdoc is present in the same regex:
    #
    # Variant #1 - rdoc not installed
    #
    #   <b>invalidhomepagegem 1</b>
    #
    #
    #  <span title="rdoc not installed">[rdoc]</span>
    #
    #
    #
    #  <a href="." title=".">[www]</a>
    #
    # Variant #2 - rdoc installed
    #
    #   <b>invalidhomepagegem 1</b>
    #
    #
    #  <a href="\/doc_root\/invalidhomepagegem-1\/">\[rdoc\]<\/a>
    #
    #
    #
    #  <a href="." title=".">[www]</a>
    regex_match = /invalidhomepagegem 1<\/b>[\s]+(<span title="rdoc not installed">\[rdoc\]<\/span>|<a href="\/doc_root\/invalidhomepagegem-1\/">\[rdoc\]<\/a>)[\s]+<a href="\." title="\.">\[www\]<\/a>/
    assert_match regex_match, @res.body
  end

  def test_valid_homepage_http
    data = StringIO.new "GET / HTTP/1.0\r\n\r\n"
    dir = "#{@gemhome}2"

    spec = util_spec 'validhomepagegemhttp', 1
    spec.homepage = "http://rubygems.org"

    specs_dir = File.join dir, 'specifications'
    FileUtils.mkdir_p specs_dir

    open File.join(specs_dir, spec.spec_name), 'w' do |io|
      io.write spec.to_ruby
    end

    server = Gem::Server.new dir, process_based_port, false

    @req.parse data

    server.root @req, @res

    assert_equal 200, @res.status
    assert_match 'validhomepagegemhttp 1', @res.body

    regex_match = /validhomepagegemhttp 1<\/b>[\s]+(<span title="rdoc not installed">\[rdoc\]<\/span>|<a href="\/doc_root\/validhomepagegemhttp-1\/">\[rdoc\]<\/a>)[\s]+<a href="http:\/\/rubygems\.org" title="http:\/\/rubygems\.org">\[www\]<\/a>/
    assert_match regex_match, @res.body
  end

  def test_valid_homepage_https
    data = StringIO.new "GET / HTTP/1.0\r\n\r\n"
    dir = "#{@gemhome}2"

    spec = util_spec 'validhomepagegemhttps', 1
    spec.homepage = "https://rubygems.org"

    specs_dir = File.join dir, 'specifications'
    FileUtils.mkdir_p specs_dir

    open File.join(specs_dir, spec.spec_name), 'w' do |io|
      io.write spec.to_ruby
    end

    server = Gem::Server.new dir, process_based_port, false

    @req.parse data

    server.root @req, @res

    assert_equal 200, @res.status
    assert_match 'validhomepagegemhttps 1', @res.body

    regex_match = /validhomepagegemhttps 1<\/b>[\s]+(<span title="rdoc not installed">\[rdoc\]<\/span>|<a href="\/doc_root\/validhomepagegemhttps-1\/">\[rdoc\]<\/a>)[\s]+<a href="https:\/\/rubygems\.org" title="https:\/\/rubygems\.org">\[www\]<\/a>/
    assert_match regex_match, @res.body
  end

  def test_specs
    data = StringIO.new "GET /specs.#{Gem.marshal_version} HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.specs @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'application/octet-stream', @res['content-type']

    assert_equal [['a', Gem::Version.new(1), Gem::Platform::RUBY],
                  ['a', Gem::Version.new(2), Gem::Platform::RUBY],
                  ['a', v('3.a'), Gem::Platform::RUBY]],
                 Marshal.load(@res.body)
  end

  def test_specs_gemdirs
    data = StringIO.new "GET /specs.#{Gem.marshal_version} HTTP/1.0\r\n\r\n"
    dir = "#{@gemhome}2"

    spec = util_spec 'z', 9

    specs_dir = File.join dir, 'specifications'
    FileUtils.mkdir_p specs_dir

    open File.join(specs_dir, spec.spec_name), 'w' do |io|
      io.write spec.to_ruby
    end

    server = Gem::Server.new dir, process_based_port, false

    @req.parse data

    server.specs @req, @res

    assert_equal 200, @res.status

    assert_equal [['z', v(9), Gem::Platform::RUBY]], Marshal.load(@res.body)
  end

  def test_specs_gz
    data = StringIO.new "GET /specs.#{Gem.marshal_version}.gz HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.specs @req, @res

    assert_equal 200, @res.status, @res.body
    assert_match %r| \d\d:\d\d:\d\d |, @res['date']
    assert_equal 'application/x-gzip', @res['content-type']

    assert_equal [['a', Gem::Version.new(1), Gem::Platform::RUBY],
                  ['a', Gem::Version.new(2), Gem::Platform::RUBY],
                  ['a', v('3.a'), Gem::Platform::RUBY]],
                 Marshal.load(Gem.gunzip(@res.body))
  end

  def test_uri_encode
    url_safe = @server.uri_encode 'http://rubyonrails.org/">malicious_content</a>'
    assert_equal url_safe, 'http://rubyonrails.org/%22%3Emalicious_content%3C/a%3E'
  end

  # Regression test for issue #1793: incorrect URL encoding.
  # Checking that no URLs have had '://' incorrectly encoded
  def test_regression_1793
    data = StringIO.new "GET / HTTP/1.0\r\n\r\n"
    @req.parse data

    @server.root @req, @res

    refute_match %r|%3A%2F%2F|, @res.body
  end

  def util_listen
    webrick = Object.new
    webrick.instance_variable_set :@listeners, []
    def webrick.listeners() @listeners end
    def webrick.listen(host, port)
      socket = Object.new
      socket.instance_variable_set :@host, host
      socket.instance_variable_set :@port, port
      def socket.addr() [nil, @port, @host] end
      @listeners << socket
    end

    @server.instance_variable_set :@server, webrick
  end
end
