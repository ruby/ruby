require_relative '../../spec_helper'
require_relative '../../fixtures/classes'

describe :unixsocket_new, shared: true do
  platform_is_not :windows do
    before :each do
      @path = SocketSpecs.socket_path
      @server = UNIXServer.open(@path)
    end

    after :each do
      @client.close if @client
      @server.close
      SocketSpecs.rm_socket @path
    end

    it "opens a unix socket on the specified file" do
      @client = UNIXSocket.send(@method, @path)

      @client.addr[0].should == "AF_UNIX"
      @client.should_not.closed?
    end
  end
end
