require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "TCPServer#gets" do
  before :each do
    @server = TCPServer.new(SocketSpecs.hostname, 0)
  end

  after :each do
    @server.close
  end

  it "raises Errno::ENOTCONN on gets" do
    -> { @server.gets }.should raise_error(Errno::ENOTCONN)
  end
end
