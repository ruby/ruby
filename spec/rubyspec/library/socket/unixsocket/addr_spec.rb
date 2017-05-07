require File.expand_path('../../../../spec_helper', __FILE__)
require File.expand_path('../../fixtures/classes', __FILE__)

describe "UNIXSocket#addr" do

  platform_is_not :windows do
    before :each do
      @path = SocketSpecs.socket_path
      rm_r @path

      @server = UNIXServer.open(@path)
      @client = UNIXSocket.open(@path)
    end

    after :each do
      @client.close
      @server.close
      rm_r @path
    end

    it "returns the address family of this socket in an array" do
      @client.addr[0].should == "AF_UNIX"
    end

    it "returns the path of the socket in an array if it's a server" do
      @server.addr[1].should == @path
    end

    it "returns an empty string for path if it's a client" do
      @client.addr[1].should == ""
    end

    it "returns an array" do
      @client.addr.should be_kind_of(Array)
    end
  end

end
