require File.expand_path('../../../../spec_helper', __FILE__)
require File.expand_path('../../fixtures/classes', __FILE__)
require File.expand_path('../../shared/partially_closable_sockets', __FILE__)

describe "TCPSocket partial closability" do

  before :each do
    port = SocketSpecs.find_available_port
    @server = TCPServer.new("127.0.0.1", port)
    @s1 = TCPSocket.new("127.0.0.1", port)
    @s2 = @server.accept
  end

  after :each do
    @server.close
    @s1.close
    @s2.close
  end

  it_should_behave_like "partially closable sockets"

end
