require 'timeout'

module WEBrick_Testing
  class DummyLog < WEBrick::BasicLog
    def initialize() super(self) end
    def <<(*args) end
  end
  
  def start_server(config={})
    raise "already started" if @__server_pid or @__started
    trap('HUP') { @__started = true }
    @__server_pid = fork do 
      w = WEBrick::HTTPServer.new(
        { 
          :Logger => DummyLog.new,
          :AccessLog => [],
          :StartCallback => proc { Process.kill('HUP', Process.ppid) }
        }.update(config))
      yield w
      trap('INT') { w.shutdown }
      w.start
      exit
    end

    Timeout.timeout(5) {
      nil until @__started # wait until the server is ready
    }
  end

  def stop_server
    Process.kill('INT', @__server_pid)
    @__server_pid = nil
    @__started = false
    Process.wait
    raise unless $?.success?
  end
end
