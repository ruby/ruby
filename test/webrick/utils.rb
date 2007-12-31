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

  module_function

  def start_server(klass, config={}, &block)
    server = klass.new({
      :BindAddress => "127.0.0.1", :Port => 0,
      :ShutdownSocketWithoutClose =>true,
      :ServerType => Thread,
      :Logger => WEBrick::Log.new(NullWriter),
      :AccessLog => [[NullWriter, ""]]
    }.update(config))
    begin
      server.start
      addr = server.listeners[0].addr
      block.yield([server, addr[3], addr[1]])
    ensure
      server.shutdown
      until server.status == :Stop
        sleep 0.1
      end
    end
  end

  def start_httpserver(config={}, &block)
    start_server(WEBrick::HTTPServer, config, &block)
  end

  def start_httpproxy(config={}, &block)
    start_server(WEBrick::HTTPProxyServer, config, &block)
  end
end
