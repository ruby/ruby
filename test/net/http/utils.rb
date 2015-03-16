require 'webrick'
begin
  require "webrick/https"
rescue LoadError
  # SSL features cannot be tested
end
require 'webrick/httpservlet/abstract'

module TestNetHTTPUtils
  def start(&block)
    new().start(&block)
  end

  def new
    klass = Net::HTTP::Proxy(config('proxy_host'), config('proxy_port'))
    http = klass.new(config('host'), config('port'))
    http.set_debug_output logfile()
    http
  end

  def config(key)
    @config ||= self.class::CONFIG
    @config[key]
  end

  def logfile
    $DEBUG ? $stderr : NullWriter.new
  end

  def setup
    spawn_server
  end

  def teardown
    if @server
      @server.shutdown
      @server_thread.join
    end
    @log_tester.call(@log) if @log_tester
    # resume global state
    Net::HTTP.version_1_2
  end

  def spawn_server
    @log = []
    @log_tester = lambda {|log| assert_equal([], log ) }
    @config = self.class::CONFIG
    server_config = {
      :BindAddress => config('host'),
      :Port => 0,
      :Logger => WEBrick::Log.new(@log, WEBrick::BasicLog::WARN),
      :AccessLog => [],
      :ServerType => Thread,
    }
    server_config[:OutputBufferSize] = 4 if config('chunked')
    server_config[:RequestTimeout] = config('RequestTimeout') if config('RequestTimeout')
    if defined?(OpenSSL) and config('ssl_enable')
      server_config.update({
        :SSLEnable      => true,
        :SSLCertificate => config('ssl_certificate'),
        :SSLPrivateKey  => config('ssl_private_key'),
        :SSLTmpDhCallback => proc { OpenSSL::TestUtils::TEST_KEY_DH1024 },
      })
    end
    @server = WEBrick::HTTPServer.new(server_config)
    @server.mount('/', Servlet, config('chunked'))
    @server_thread = @server.start
    @config['port'] = @server[:Port]
  end

  $test_net_http = nil
  $test_net_http_data = (0...256).to_a.map {|i| i.chr }.join('') * 64
  $test_net_http_data.force_encoding("ASCII-8BIT")
  $test_net_http_data_type = 'application/octet-stream'

  class Servlet < WEBrick::HTTPServlet::AbstractServlet
    def initialize(this, chunked = false)
      @chunked = chunked
    end

    def do_GET(req, res)
      res['Content-Type'] = $test_net_http_data_type
      res.body = $test_net_http_data
      res.chunked = @chunked
    end

    # echo server
    def do_POST(req, res)
      res['Content-Type'] = req['Content-Type']
      res['X-request-uri'] = req.request_uri.to_s
      res.body = req.body
      res.chunked = @chunked
    end

    def do_PATCH(req, res)
      res['Content-Type'] = req['Content-Type']
      res.body = req.body
      res.chunked = @chunked
    end
  end

  class NullWriter
    def <<(s) end
    def puts(*args) end
    def print(*args) end
    def printf(*args) end
  end
end
