require 'soap/rpc/standaloneServer'

class HelloWorldServer < SOAP::RPC::StandaloneServer
  def on_init
    @soaplet.allow_content_encoding_gzip = true
    @log.level = Logger::Severity::DEBUG
    add_method(self, 'hello_world', 'from')
  end

  def hello_world(from)
    "Hello World, from #{ from }"
  end
end

if $0 == __FILE__
  server = HelloWorldServer.new('hws', 'urn:hws', '0.0.0.0', 2000)
  trap(:INT) do 
    server.shutdown
  end
  server.start
end
