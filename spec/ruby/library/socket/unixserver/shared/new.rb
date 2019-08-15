require_relative '../../spec_helper'
require_relative '../../fixtures/classes'

describe :unixserver_new, shared: true do
  platform_is_not :windows do
    before :each do
      @path = SocketSpecs.socket_path
    end

    after :each do
      @server.close if @server
      @server = nil
      SocketSpecs.rm_socket @path
    end

    it "creates a new UNIXServer" do
      @server = UNIXServer.send(@method, @path)
      @server.path.should == @path
      @server.addr.should == ["AF_UNIX", @path]
    end
  end
end
