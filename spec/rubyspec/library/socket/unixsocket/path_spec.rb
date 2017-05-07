require File.expand_path('../../../../spec_helper', __FILE__)
require File.expand_path('../../fixtures/classes', __FILE__)

describe "UNIXSocket#path" do

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

    it "returns the path of the socket if it's a server" do
      @server.path.should == @path
    end

    it "returns an empty string for path if it's a client" do
      @client.path.should == ""
    end
  end

end
