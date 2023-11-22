require_relative '../spec_helper'
require_relative '../fixtures/classes'

with_feature :unix_socket do
  describe "UNIXSocket#peeraddr" do
    before :each do
      @path = SocketSpecs.socket_path
      @server = UNIXServer.open(@path)
      @client = UNIXSocket.open(@path)
    end

    after :each do
      @client.close
      @server.close
      SocketSpecs.rm_socket @path
    end

    it "returns the address family and path of the server end of the connection" do
      @client.peeraddr.should == ["AF_UNIX", @path]
    end

    it "raises an error in server sockets" do
      -> {
        @server.peeraddr
      }.should raise_error(Errno::ENOTCONN)
    end
  end
end
