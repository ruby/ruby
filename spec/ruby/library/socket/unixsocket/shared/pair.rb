require_relative '../../spec_helper'
require_relative '../../fixtures/classes'

describe :unixsocket_pair, shared: true do
  it "returns two UNIXSockets" do
    @s1.should be_an_instance_of(UNIXSocket)
    @s2.should be_an_instance_of(UNIXSocket)
  end

  it "returns a pair of connected sockets" do
    @s1.puts "foo"
    @s2.gets.should == "foo\n"
  end

  platform_is_not :windows do
    it "sets the socket paths to empty Strings" do
      @s1.path.should == ""
      @s2.path.should == ""
    end

    it "sets the socket addresses to empty Strings" do
      @s1.addr.should == ["AF_UNIX", ""]
      @s2.addr.should == ["AF_UNIX", ""]
    end

    it "sets the socket peer addresses to empty Strings" do
      @s1.peeraddr.should == ["AF_UNIX", ""]
      @s2.peeraddr.should == ["AF_UNIX", ""]
    end
  end

  platform_is :windows do
    it "emulates unnamed sockets with a temporary file with a path" do
      @s1.addr.should == ["AF_UNIX", @s1.path]
      @s2.peeraddr.should == ["AF_UNIX", @s1.path]
    end

    it "sets the peer address of first socket to an empty string" do
      @s1.peeraddr.should == ["AF_UNIX", ""]
    end

    it "sets the address and path of second socket to an empty string" do
      @s2.addr.should == ["AF_UNIX", ""]
      @s2.path.should == ""
    end
  end
end
