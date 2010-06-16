begin
  loadpath = $:.dup
  $:.replace($: | [File.expand_path("../ruby", File.dirname(__FILE__))])
  require 'envutil'
ensure
  $:.replace(loadpath)
end
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

  RubyBin = "\"#{EnvUtil.rubybin}\""
  RubyBin << " \"-I#{File.expand_path("../..", File.dirname(__FILE__))}/lib\""
  RubyBin << " \"-I#{File.dirname(EnvUtil.rubybin)}/.ext/common\""
  RubyBin << " \"-I#{File.dirname(EnvUtil.rubybin)}/.ext/#{RUBY_PLATFORM}\""

  module_function

  def start_server(klass, config={}, &block)
    log_string = ""
    logger = Object.new
    class << logger; self; end.class_eval do
      define_method(:<<) {|msg| log_string << msg }
    end
    log = proc { "webrick log start:\n" + log_string.gsub(/^/, "  ").chomp + "\nwebrick log end" }
    server = klass.new({
      :BindAddress => "127.0.0.1", :Port => 0,
      :Logger => WEBrick::Log.new(logger),
      :AccessLog => [[NullWriter, ""]]
    }.update(config))
    begin
      thread = Thread.start{ server.start }
      addr = server.listeners[0].addr
      block.call([server, addr[3], addr[1], log])
    ensure
      server.stop
      thread.join
    end
  end

  def start_httpserver(config={}, &block)
    start_server(WEBrick::HTTPServer, config, &block)
  end

  def start_httpproxy(config={}, &block)
    start_server(WEBrick::HTTPProxyServer, config, &block)
  end
end
