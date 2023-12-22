require_relative '../spec_helper'
require_relative '../fixtures/classes'
require_relative '../shared/partially_closable_sockets'

with_feature :unix_socket do
  describe "UNIXSocket#pair" do
    it_should_behave_like :partially_closable_sockets

    before :each do
      @s1, @s2 = UNIXSocket.pair
    end

    after :each do
      @s1.close
      @s2.close
    end

    it "returns a pair of connected sockets" do
      @s1.puts "foo"
      @s2.gets.should == "foo\n"
    end

    it "returns sockets with no name" do
      @s1.path.should == @s2.path
      @s1.path.should == ""
    end

    it "returns sockets with no address" do
      @s1.addr.should == ["AF_UNIX", ""]
      @s2.addr.should == ["AF_UNIX", ""]
    end

    it "returns sockets with no peeraddr" do
      @s1.peeraddr.should == ["AF_UNIX", ""]
      @s2.peeraddr.should == ["AF_UNIX", ""]
    end
  end
end
