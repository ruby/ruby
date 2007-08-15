require 'soap/rpc/standaloneServer'

class HelloWorldServer < SOAP::RPC::StandaloneServer
  def on_init
    add_method(self, 'hello_world', 'from')
  end

  def hello_world(from)
    "Hello World, from #{ from }"
  end
end

if $0 == __FILE__
  server = HelloWorldServer.new('hws', 'urn:hws', '0.0.0.0', 17171)
  server.start
end
