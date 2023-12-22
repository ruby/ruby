require_relative '../spec_helper'
require_relative '../fixtures/classes'
require_relative 'shared/new'

with_feature :unix_socket do
  describe "UNIXServer.open" do
    it_behaves_like :unixserver_new, :open

    before :each do
      @path = SocketSpecs.socket_path
    end

    after :each do
      @server.close if @server
      @server = nil
      SocketSpecs.rm_socket @path
    end

    it "yields the new UNIXServer object to the block, if given" do
      UNIXServer.open(@path) do |unix|
        unix.path.should == @path
        unix.addr.should == ["AF_UNIX", @path]
      end
    end
  end
end
