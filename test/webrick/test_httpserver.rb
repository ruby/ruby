# frozen_string_literal: false
require "test/unit"
require "net/http"
require "webrick"
require_relative "utils"

class TestWEBrickHTTPServer < Test::Unit::TestCase
  empty_log = Object.new
  def empty_log.<<(str)
    assert_equal('', str)
    self
  end
  NoLog = WEBrick::Log.new(empty_log, WEBrick::BasicLog::WARN)

  def test_mount
    httpd = WEBrick::HTTPServer.new(
      :Logger => NoLog,
      :DoNotListen=>true
    )
    httpd.mount("/", :Root)
    httpd.mount("/foo", :Foo)
    httpd.mount("/foo/bar", :Bar, :bar1)
    httpd.mount("/foo/bar/baz", :Baz, :baz1, :baz2)

    serv, opts, script_name, path_info = httpd.search_servlet("/")
    assert_equal(:Root, serv)
    assert_equal([], opts)
    assert_equal("", script_name)
    assert_equal("/", path_info)

    serv, opts, script_name, path_info = httpd.search_servlet("/sub")
    assert_equal(:Root, serv)
    assert_equal([], opts)
    assert_equal("", script_name)
    assert_equal("/sub", path_info)

    serv, opts, script_name, path_info = httpd.search_servlet("/sub/")
    assert_equal(:Root, serv)
    assert_equal([], opts)
    assert_equal("", script_name)
    assert_equal("/sub/", path_info)

    serv, opts, script_name, path_info = httpd.search_servlet("/foo")
    assert_equal(:Foo, serv)
    assert_equal([], opts)
    assert_equal("/foo", script_name)
    assert_equal("", path_info)

    serv, opts, script_name, path_info = httpd.search_servlet("/foo/")
    assert_equal(:Foo, serv)
    assert_equal([], opts)
    assert_equal("/foo", script_name)
    assert_equal("/", path_info)

    serv, opts, script_name, path_info = httpd.search_servlet("/foo/sub")
    assert_equal(:Foo, serv)
    assert_equal([], opts)
    assert_equal("/foo", script_name)
    assert_equal("/sub", path_info)

    serv, opts, script_name, path_info = httpd.search_servlet("/foo/bar")
    assert_equal(:Bar, serv)
    assert_equal([:bar1], opts)
    assert_equal("/foo/bar", script_name)
    assert_equal("", path_info)

    serv, opts, script_name, path_info = httpd.search_servlet("/foo/bar/baz")
    assert_equal(:Baz, serv)
    assert_equal([:baz1, :baz2], opts)
    assert_equal("/foo/bar/baz", script_name)
    assert_equal("", path_info)
  end

  class Req
    attr_reader :port, :host
    def initialize(addr, port, host)
      @addr, @port, @host = addr, port, host
    end
    def addr
      [0,0,0,@addr]
    end
  end

  def httpd(addr, port, host, ali)
    config ={
      :Logger      => NoLog,
      :DoNotListen => true,
      :BindAddress => addr,
      :Port        => port,
      :ServerName  => host,
      :ServerAlias => ali,
    }
    return WEBrick::HTTPServer.new(config)
  end

  def assert_eql?(v1, v2)
    assert_equal(v1.object_id, v2.object_id)
  end

  def test_lookup_server
    addr1  = "192.168.100.1"
    addr2  = "192.168.100.2"
    addrz  = "192.168.100.254"
    local  = "127.0.0.1"
    port1  = 80
    port2  = 8080
    port3  = 10080
    portz  = 32767
    name1  = "www.example.com"
    name2  = "www2.example.com"
    name3  = "www3.example.com"
    namea  = "www.example.co.jp"
    nameb  = "www.example.jp"
    namec  = "www2.example.co.jp"
    named  = "www2.example.jp"
    namez  = "foobar.example.com"
    alias1 = [namea, nameb]
    alias2 = [namec, named]

    host1 = httpd(nil, port1, name1, nil)
    hosts = [
      host2  = httpd(addr1, port1, name1, nil),
      host3  = httpd(addr1, port1, name2, alias1),
      host4  = httpd(addr1, port2, name1, nil),
      host5  = httpd(addr1, port2, name2, alias1),
               httpd(addr1, port2, name3, alias2),
      host7  = httpd(addr2, nil,   name1, nil),
      host8  = httpd(addr2, nil,   name2, alias1),
               httpd(addr2, nil,   name3, alias2),
      host10 = httpd(local, nil,   nil,   nil),
      host11 = httpd(nil,   port3, nil,   nil),
    ].sort_by{ rand }
    hosts.each{|h| host1.virtual_host(h) }

    # connect to addr1
    assert_eql?(host2,   host1.lookup_server(Req.new(addr1, port1, name1)))
    assert_eql?(host3,   host1.lookup_server(Req.new(addr1, port1, name2)))
    assert_eql?(host3,   host1.lookup_server(Req.new(addr1, port1, namea)))
    assert_eql?(host3,   host1.lookup_server(Req.new(addr1, port1, nameb)))
    assert_eql?(nil,     host1.lookup_server(Req.new(addr1, port1, namez)))
    assert_eql?(host4,   host1.lookup_server(Req.new(addr1, port2, name1)))
    assert_eql?(host5,   host1.lookup_server(Req.new(addr1, port2, name2)))
    assert_eql?(host5,   host1.lookup_server(Req.new(addr1, port2, namea)))
    assert_eql?(host5,   host1.lookup_server(Req.new(addr1, port2, nameb)))
    assert_eql?(nil,     host1.lookup_server(Req.new(addr1, port2, namez)))
    assert_eql?(host11,  host1.lookup_server(Req.new(addr1, port3, name1)))
    assert_eql?(host11,  host1.lookup_server(Req.new(addr1, port3, name2)))
    assert_eql?(host11,  host1.lookup_server(Req.new(addr1, port3, namea)))
    assert_eql?(host11,  host1.lookup_server(Req.new(addr1, port3, nameb)))
    assert_eql?(host11,  host1.lookup_server(Req.new(addr1, port3, namez)))
    assert_eql?(nil,     host1.lookup_server(Req.new(addr1, portz, name1)))
    assert_eql?(nil,     host1.lookup_server(Req.new(addr1, portz, name2)))
    assert_eql?(nil,     host1.lookup_server(Req.new(addr1, portz, namea)))
    assert_eql?(nil,     host1.lookup_server(Req.new(addr1, portz, nameb)))
    assert_eql?(nil,     host1.lookup_server(Req.new(addr1, portz, namez)))

    # connect to addr2
    assert_eql?(host7,  host1.lookup_server(Req.new(addr2, port1, name1)))
    assert_eql?(host8,  host1.lookup_server(Req.new(addr2, port1, name2)))
    assert_eql?(host8,  host1.lookup_server(Req.new(addr2, port1, namea)))
    assert_eql?(host8,  host1.lookup_server(Req.new(addr2, port1, nameb)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addr2, port1, namez)))
    assert_eql?(host7,  host1.lookup_server(Req.new(addr2, port2, name1)))
    assert_eql?(host8,  host1.lookup_server(Req.new(addr2, port2, name2)))
    assert_eql?(host8,  host1.lookup_server(Req.new(addr2, port2, namea)))
    assert_eql?(host8,  host1.lookup_server(Req.new(addr2, port2, nameb)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addr2, port2, namez)))
    assert_eql?(host7,  host1.lookup_server(Req.new(addr2, port3, name1)))
    assert_eql?(host8,  host1.lookup_server(Req.new(addr2, port3, name2)))
    assert_eql?(host8,  host1.lookup_server(Req.new(addr2, port3, namea)))
    assert_eql?(host8,  host1.lookup_server(Req.new(addr2, port3, nameb)))
    assert_eql?(host11, host1.lookup_server(Req.new(addr2, port3, namez)))
    assert_eql?(host7,  host1.lookup_server(Req.new(addr2, portz, name1)))
    assert_eql?(host8,  host1.lookup_server(Req.new(addr2, portz, name2)))
    assert_eql?(host8,  host1.lookup_server(Req.new(addr2, portz, namea)))
    assert_eql?(host8,  host1.lookup_server(Req.new(addr2, portz, nameb)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addr2, portz, namez)))

    # connect to addrz
    assert_eql?(nil,    host1.lookup_server(Req.new(addrz, port1, name1)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addrz, port1, name2)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addrz, port1, namea)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addrz, port1, nameb)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addrz, port1, namez)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addrz, port2, name1)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addrz, port2, name2)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addrz, port2, namea)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addrz, port2, nameb)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addrz, port2, namez)))
    assert_eql?(host11, host1.lookup_server(Req.new(addrz, port3, name1)))
    assert_eql?(host11, host1.lookup_server(Req.new(addrz, port3, name2)))
    assert_eql?(host11, host1.lookup_server(Req.new(addrz, port3, namea)))
    assert_eql?(host11, host1.lookup_server(Req.new(addrz, port3, nameb)))
    assert_eql?(host11, host1.lookup_server(Req.new(addrz, port3, namez)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addrz, portz, name1)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addrz, portz, name2)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addrz, portz, namea)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addrz, portz, nameb)))
    assert_eql?(nil,    host1.lookup_server(Req.new(addrz, portz, namez)))

    # connect to localhost
    assert_eql?(host10, host1.lookup_server(Req.new(local, port1, name1)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, port1, name2)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, port1, namea)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, port1, nameb)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, port1, namez)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, port2, name1)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, port2, name2)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, port2, namea)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, port2, nameb)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, port2, namez)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, port3, name1)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, port3, name2)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, port3, namea)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, port3, nameb)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, port3, namez)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, portz, name1)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, portz, name2)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, portz, namea)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, portz, nameb)))
    assert_eql?(host10, host1.lookup_server(Req.new(local, portz, namez)))
  end

  def test_callbacks
    accepted = started = stopped = 0
    requested0 = requested1 = 0
    config = {
      :ServerName => "localhost",
      :AcceptCallback => Proc.new{ accepted += 1 },
      :StartCallback => Proc.new{ started += 1 },
      :StopCallback => Proc.new{ stopped += 1 },
      :RequestCallback => Proc.new{|req, res| requested0 += 1 },
    }
    log_tester = lambda {|log, access_log|
      assert(log.find {|s| %r{ERROR `/' not found\.} =~ s })
      assert_equal([], log.reject {|s| %r{ERROR `/' not found\.} =~ s })
    }
    TestWEBrick.start_httpserver(config, log_tester){|server, addr, port, log|
      vhost_config = {
        :ServerName => "myhostname",
        :BindAddress => addr,
        :Port => port,
        :DoNotListen => true,
        :Logger => NoLog,
        :AccessLog => [],
        :RequestCallback => Proc.new{|req, res| requested1 += 1 },
      }
      server.virtual_host(WEBrick::HTTPServer.new(vhost_config))

      Thread.pass while server.status != :Running
      assert_equal(1, started, log.call)
      assert_equal(0, stopped, log.call)
      assert_equal(0, accepted, log.call)

      http = Net::HTTP.new(addr, port)
      req = Net::HTTP::Get.new("/")
      req["Host"] = "myhostname:#{port}"
      http.request(req){|res| assert_equal("404", res.code, log.call)}
      http.request(req){|res| assert_equal("404", res.code, log.call)}
      http.request(req){|res| assert_equal("404", res.code, log.call)}
      req["Host"] = "localhost:#{port}"
      http.request(req){|res| assert_equal("404", res.code, log.call)}
      http.request(req){|res| assert_equal("404", res.code, log.call)}
      http.request(req){|res| assert_equal("404", res.code, log.call)}
      assert_equal(6, accepted, log.call)
      assert_equal(3, requested0, log.call)
      assert_equal(3, requested1, log.call)
    }
    assert_equal(started, 1)
    assert_equal(stopped, 1)
  end

  # This class is needed by test_response_io_with_chunked_set method
  class EventManagerForChunkedResponseTest
    def initialize
      @listeners = []
    end
    def add_listener( &block )
      @listeners << block
    end
    def raise_str_event( str )
      @listeners.each{ |e| e.call( :str, str ) }
    end
    def raise_close_event()
      @listeners.each{ |e| e.call( :cls ) }
    end
  end
  def test_response_io_with_chunked_set
    evt_man = EventManagerForChunkedResponseTest.new
    t = Thread.new do
      begin
        config = {
          :ServerName => "localhost"
        }
        TestWEBrick.start_httpserver(config) do |server, addr, port, log|
          body_strs = [ 'aaaaaa', 'bb', 'cccc' ]
          server.mount_proc( "/", ->( req, res ){
            # Test for setting chunked...
            res.chunked = true
            r,w = IO.pipe
            evt_man.add_listener do |type,str|
              type == :cls ? ( w.close ) : ( w << str )
            end
            res.body = r
          } )
          Thread.pass while server.status != :Running
          http = Net::HTTP.new(addr, port)
          req  = Net::HTTP::Get.new("/")
          http.request(req) do |res|
            i = 0
            evt_man.raise_str_event( body_strs[i] )
            res.read_body do |s|
              assert_equal( body_strs[i], s )
              i += 1
              if i < body_strs.length
                evt_man.raise_str_event( body_strs[i] )
              else
                evt_man.raise_close_event()
              end
            end
            assert_equal( body_strs.length, i )
          end
        end
      rescue => err
        flunk( 'exception raised in thread: ' + err.to_s )
      end
    end
    if t.join( 3 ).nil?
      evt_man.raise_close_event()
      flunk( 'timeout' )
      if t.join( 1 ).nil?
        Thread.kill t
      end
    end
  end

  def test_response_io_without_chunked_set
    config = {
      :ServerName => "localhost"
    }
    log_tester = lambda {|log, access_log|
      assert_equal(1, log.length)
      assert_match(/WARN  Could not determine content-length of response body./, log[0])
    }
    TestWEBrick.start_httpserver(config, log_tester){|server, addr, port, log|
      server.mount_proc("/", lambda { |req, res|
        r,w = IO.pipe
        # Test for not setting chunked...
        # res.chunked = true
        res.body = r
        w << "foo"
        w.close
      })
      Thread.pass while server.status != :Running
      http = Net::HTTP.new(addr, port)
      req = Net::HTTP::Get.new("/")
      req['Connection'] = 'Keep-Alive'
      begin
        Timeout.timeout(2) do
          http.request(req){|res| assert_equal("foo", res.body) }
        end
      rescue Timeout::Error
        flunk('corrupted response')
      end
    }
  end

  def test_request_handler_callback_is_deprecated
    requested = 0
    config = {
      :ServerName => "localhost",
      :RequestHandler => Proc.new{|req, res| requested += 1 },
    }
    log_tester = lambda {|log, access_log|
      assert_equal(2, log.length)
      assert_match(/WARN  :RequestHandler is deprecated, please use :RequestCallback/, log[0])
      assert_match(%r{ERROR `/' not found\.}, log[1])
    }
    TestWEBrick.start_httpserver(config, log_tester){|server, addr, port, log|
      Thread.pass while server.status != :Running

      http = Net::HTTP.new(addr, port)
      req = Net::HTTP::Get.new("/")
      req["Host"] = "localhost:#{port}"
      http.request(req){|res| assert_equal("404", res.code, log.call)}
      assert_match(%r{:RequestHandler is deprecated, please use :RequestCallback$}, log.call, log.call)
    }
    assert_equal(1, requested)
  end

  def test_shutdown_with_busy_keepalive_connection
    requested = 0
    config = {
      :ServerName => "localhost",
    }
    TestWEBrick.start_httpserver(config){|server, addr, port, log|
      server.mount_proc("/", lambda {|req, res| res.body = "heffalump" })
      Thread.pass while server.status != :Running

      Net::HTTP.start(addr, port) do |http|
        req = Net::HTTP::Get.new("/")
        http.request(req){|res| assert_equal('Keep-Alive', res['Connection'], log.call) }
        server.shutdown
        begin
          10.times {|n| http.request(req); requested += 1 }
        rescue
          # Errno::ECONNREFUSED or similar
        end
      end
    }
    assert_equal(0, requested, "Server responded to #{requested} requests after shutdown")
  end

  def test_cntrl_in_path
    log_ary = []
    access_log_ary = []
    config = {
      :Port => 0,
      :BindAddress => '127.0.0.1',
      :Logger => WEBrick::Log.new(log_ary, WEBrick::BasicLog::WARN),
      :AccessLog => [[access_log_ary, '']],
    }
    s = WEBrick::HTTPServer.new(config)
    s.mount('/foo', WEBrick::HTTPServlet::FileHandler, __FILE__)
    th = Thread.new { s.start }
    addr = s.listeners[0].addr

    http = Net::HTTP.new(addr[3], addr[1])
    req = Net::HTTP::Get.new('/notexist%0a/foo')
    http.request(req) { |res| assert_equal('404', res.code) }
    exp = %Q(ERROR `/notexist\\n/foo' not found.\n)
    assert_equal 1, log_ary.size
    assert log_ary[0].include?(exp)
  ensure
    s&.shutdown
    th&.join
  end
end
