require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket#listen" do
  before :each do
    @socket = Socket.new(Socket::AF_INET, Socket::SOCK_STREAM, 0)
  end

  after :each do
    @socket.closed?.should be_false
    @socket.close
  end

  it "verifies we can listen for incoming connections" do
    sockaddr = Socket.pack_sockaddr_in(0, "127.0.0.1")
    @socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
    @socket.bind(sockaddr)
    @socket.listen(1).should == 0
  end
end

describe 'Socket#listen' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    describe 'using a DGRAM socket' do
      before do
        @server = Socket.new(family, :DGRAM)
        @client = Socket.new(family, :DGRAM)

        @server.bind(Socket.sockaddr_in(0, ip_address))
      end

      after do
        @client.close
        @server.close
      end

      platform_is_not :android do
        it 'raises Errno::EOPNOTSUPP' do
          -> { @server.listen(1) }.should raise_error(Errno::EOPNOTSUPP)
        end
      end

      platform_is :android do
        it 'raises Errno::EOPNOTSUPP or Errno::EACCES' do
          -> { @server.listen(1) }.should raise_error(-> exc { Errno::EACCES === exc || Errno::EOPNOTSUPP === exc })
        end
      end
    end

    describe 'using a STREAM socket' do
      before do
        @server = Socket.new(family, :STREAM)
        @client = Socket.new(family, :STREAM)

        @server.bind(Socket.sockaddr_in(0, ip_address))
      end

      after do
        @client.close
        @server.close
      end

      it 'returns 0' do
        @server.listen(1).should == 0
      end

      it "raises when the given argument can't be coerced to an Integer" do
        -> { @server.listen('cats') }.should raise_error(TypeError)
      end
    end
  end
end
