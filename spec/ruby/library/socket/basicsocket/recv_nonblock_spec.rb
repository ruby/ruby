require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket::BasicSocket#recv_nonblock" do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    before :each do
      @s1 = Socket.new(family, :DGRAM)
      @s2 = Socket.new(family, :DGRAM)
    end

    after :each do
      @s1.close unless @s1.closed?
      @s2.close unless @s2.closed?
    end

    platform_is_not :windows do
      describe 'using an unbound socket' do
        it 'raises an exception extending IO::WaitReadable' do
          lambda { @s1.recv_nonblock(1) }.should raise_error(IO::WaitReadable)
        end
      end
    end

    it "raises an exception extending IO::WaitReadable if there's no data available" do
      @s1.bind(Socket.pack_sockaddr_in(0, ip_address))
      lambda {
        @s1.recv_nonblock(5)
      }.should raise_error(IO::WaitReadable) { |e|
        platform_is_not :windows do
          e.should be_kind_of(Errno::EAGAIN)
        end
        platform_is :windows do
          e.should be_kind_of(Errno::EWOULDBLOCK)
        end
      }
    end

    it "receives data after it's ready" do
      @s1.bind(Socket.pack_sockaddr_in(0, ip_address))
      @s2.send("aaa", 0, @s1.getsockname)
      IO.select([@s1], nil, nil, 2)
      @s1.recv_nonblock(5).should == "aaa"
    end

    it "allows an output buffer as third argument" do
      @s1.bind(Socket.pack_sockaddr_in(0, ip_address))
      @s2.send("data", 0, @s1.getsockname)
      IO.select([@s1], nil, nil, 2)

      buf = "foo"
      @s1.recv_nonblock(5, 0, buf)
      buf.should == "data"
    end

    it "does not block if there's no data available" do
      @s1.bind(Socket.pack_sockaddr_in(0, ip_address))
      @s2.send("a", 0, @s1.getsockname)
      IO.select([@s1], nil, nil, 2)
      @s1.recv_nonblock(1).should == "a"
      lambda {
        @s1.recv_nonblock(5)
      }.should raise_error(IO::WaitReadable)
    end
  end
end
