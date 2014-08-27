require_relative '../ruby/envutil'
require "webrick"
begin
  require "webrick/https"
rescue LoadError
end
require "webrick/httpproxy"

module TestWEBrick
  NullWriter = Object.new
  def NullWriter.<<(msg)
    puts msg if $DEBUG
    return self
  end

  class WEBrick::HTTPServlet::CGIHandler
    remove_const :Ruby
    Ruby = EnvUtil.rubybin
    remove_const :CGIRunner
    CGIRunner = "\"#{Ruby}\" \"#{WEBrick::Config::LIBDIR}/httpservlet/cgi_runner.rb\"" # :nodoc:
  end

  RubyBin = "\"#{EnvUtil.rubybin}\""
  RubyBin << " --disable-gems"
  RubyBin << " \"-I#{File.expand_path("../..", File.dirname(__FILE__))}/lib\""
  RubyBin << " \"-I#{File.dirname(EnvUtil.rubybin)}/.ext/common\""
  RubyBin << " \"-I#{File.dirname(EnvUtil.rubybin)}/.ext/#{RUBY_PLATFORM}\""

  module_function

  def start_server(klass, config={}, &block)
    log_string = ""
    logger = Object.new
    logger.instance_eval do
      define_singleton_method(:<<) {|msg| log_string << msg }
    end
    log = proc { "webrick log start:\n" + log_string.gsub(/^/, "  ").chomp + "\nwebrick log end" }
    server = klass.new({
      :BindAddress => "127.0.0.1", :Port => 0,
      :ServerType => Thread,
      :Logger => WEBrick::Log.new(logger),
      :AccessLog => [[logger, ""]]
    }.update(config))
    begin
      server_thread = server.start
      addr = server.listeners[0].addr
      block.yield([server, addr[3], addr[1], log])
    ensure
      server.shutdown

      server_thread.join
    end
    log_string
  end

  def start_httpserver(config={}, &block)
    start_server(WEBrick::HTTPServer, config, &block)
  end

  def start_httpproxy(config={}, &block)
    start_server(WEBrick::HTTPProxyServer, config, &block)
  end
end
