require File.expand_path('../../../../spec_helper', __FILE__)
require File.expand_path('../../fixtures/classes', __FILE__)

describe "TCPServer#<<" do
  after :each do
    @server.close if @server
    @socket.close if @socket
  end
end
