require_relative '../spec_helper'
require_relative '../fixtures/classes'

platform_is_not :windows do
  describe "UNIXServer#for_fd" do
    before :each do
      @unix_path = SocketSpecs.socket_path
      @unix = UNIXServer.new(@unix_path)
    end

    after :each do
      @unix.close if @unix
      SocketSpecs.rm_socket @unix_path
    end

    it "can calculate the path" do
      b = UNIXServer.for_fd(@unix.fileno)
      b.autoclose = false

      b.path.should == @unix_path
    end
  end
end
