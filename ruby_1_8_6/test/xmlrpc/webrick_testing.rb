require 'timeout'

module WEBrick_Testing
  class DummyLog < WEBrick::BasicLog
    def initialize() super(self) end
    def <<(*args) end
  end
  
  def start_server(config={})
    raise "already started" if @__server
    @__started = false

    Thread.new {
      @__server = WEBrick::HTTPServer.new(
        { 
          :Logger => DummyLog.new,
          :AccessLog => [],
          :StartCallback => proc { @__started = true }
        }.update(config))
      yield @__server 
      @__server.start
      @__started = false
    }

    Timeout.timeout(5) {
      nil until @__started # wait until the server is ready
    }
  end

  def stop_server
    Timeout.timeout(5) {
      @__server.shutdown
      nil while @__started # wait until the server is down
    }
    @__server = nil
  end
end
