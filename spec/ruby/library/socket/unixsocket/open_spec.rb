require_relative '../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/new'

describe "UNIXSocket.open" do
  it_behaves_like :unixsocket_new, :open
end

describe "UNIXSocket.open" do
  platform_is_not :windows do
    before :each do
      @path = SocketSpecs.socket_path
      @server = UNIXServer.open(@path)
    end

    after :each do
      @server.close
      SocketSpecs.rm_socket @path
    end

    it "opens a unix socket on the specified file and yields it to the block" do
      UNIXSocket.open(@path) do |client|
        client.addr[0].should == "AF_UNIX"
        client.closed?.should == false
      end
    end
  end
end
