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
      :Logger => WEBrick::Log.new(NullWriter),
      :AccessLog => [[NullWriter, ""]]
    }.update(config))
    begin
      thread = Thread.start{ server.start }
      addr = server.listeners[0].addr
      block.call([server, addr[3], addr[1]])
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
