require_relative '../spec_helper'
require_relative '../fixtures/classes'
require_relative '../shared/partially_closable_sockets'

describe "UNIXSocket.pair" do
  it_should_behave_like :partially_closable_sockets

  before :each do
    @s1, @s2 = UNIXSocket.pair
  end

  after :each do
    @s1.close
    @s2.close
  end

  it "returns two UNIXSockets" do
    @s1.should.instance_of?(UNIXSocket)
    @s2.should.instance_of?(UNIXSocket)
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

  it "yields the sockets, returns the block's value and closes them afterwards" do
    sockets = nil
    UNIXSocket.pair { |s1, s2| sockets = [s1, s2]; :result }.should == :result
    sockets.map(&:closed?).should == [true, true]
  end

  it "closes the sockets when the block raises" do
    sockets = nil
    -> { UNIXSocket.pair { |s1, s2| sockets = [s1, s2]; raise "boom" } }.should.raise(RuntimeError, "boom")
    sockets.map(&:closed?).should == [true, true]
  end

  it "ignores a StandardError from closing a socket and still closes the other one" do
    sockets = nil
    UNIXSocket.pair do |s1, s2|
      sockets = [s1, s2]
      def s2.close
        raise IOError, "close failed"
      end
      :result
    end.should == :result
    sockets[0].should.closed?
    $!.should == nil
  ensure
    IO.instance_method(:close).bind_call(sockets[1]) if sockets
  end
end
