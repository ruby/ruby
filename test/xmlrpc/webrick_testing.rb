require 'timeout'

module TestXMLRPC
module WEBrick_Testing
  class DummyLog < WEBrick::BasicLog
    def initialize() super(self) end
    def <<(*args) end
  end

  def start_server(config={})
    raise "already started" if defined?(@__server) && @__server
    @__started = false

    @__server = WEBrick::HTTPServer.new(
      {
        :BindAddress => "localhost",
        :Logger => DummyLog.new,
        :AccessLog => [],
      }.update(config))
    yield @__server
    @__started = true

    addr = @__server.listeners.first.connect_address

    @__server_thread = Thread.new {
      begin
        @__server.start
      rescue IOError => e
        assert_match(/closed/, e.message)
      ensure
        @__started = false
      end
    }

    addr
  end

  def stop_server
    return if !defined?(@__server) || !@__server
    Timeout.timeout(5) {
      @__server.shutdown
      Thread.pass while @__started # wait until the server is down
    }
    @__server_thread.join
    @__server = nil
  end
end
end
