require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "UNIXSocket#recvfrom" do
  before :each do
    @path = SocketSpecs.socket_path
    @server = UNIXServer.open(@path)
    @client = UNIXSocket.open(@path)
  end

  after :each do
    @client.close
    @server.close
    SocketSpecs.rm_socket @path
  end

  it "receives len bytes from sock, returning an array containing sent data as first element" do
    @client.send("foobar", 0)
    sock = @server.accept
    sock.recvfrom(6).first.should == "foobar"
    sock.close
  end

  context "when called on a server's socket" do
    platform_is_not :windows do
      it "returns an array containing basic information on the client as second element" do
        @client.send("foobar", 0)
        sock = @server.accept
        data = sock.recvfrom(6)
        data.last.should == ["AF_UNIX", ""]
        sock.close
      end
    end

    guard -> { platform_is :windows and ruby_bug "#21702", ""..."4.2" } do
      it "returns an array containing basic information on the client as second element" do
        @client.send("foobar", 0)
        sock = @server.accept
        data = sock.recvfrom(6)
        data.last.should == ["AF_UNIX", ""]
        sock.close
      end
    end
  end

  context "when called on a client's socket" do
    platform_is :linux do
      it "returns an array containing server's address as second element" do
        @client.send("", 0)
        sock = @server.accept
        sock.send("barfoo", 0)
        @client.recvfrom(6).last.should == ["AF_UNIX", @server.local_address.unix_path]
        sock.close
      end
    end

    guard -> { platform_is :windows and ruby_bug "#21702", ""..."4.2" } do
      it "returns an array containing server's address as second element" do
        @client.send("", 0)
        sock = @server.accept
        sock.send("barfoo", 0)
        # This may not be correct, depends on what underlying recvfrom actually returns.
        @client.recvfrom(6).last.should == ["AF_UNIX", @server.local_address.unix_path]
        sock.close
      end
    end

    platform_is :darwin do
      it "returns an array containing basic information on the server as second element" do
        @client.send("", 0)
        sock = @server.accept
        sock.send("barfoo", 0)
        @client.recvfrom(6).last.should == ["AF_UNIX", ""]
        sock.close
      end
    end
  end

  it "allows an output buffer as third argument" do
    buffer = +''

    @client.send("foobar", 0)
    sock = @server.accept
    message, = sock.recvfrom(6, 0, buffer)
    sock.close

    message.should.equal?(buffer)
    buffer.should == "foobar"
  end

  it "preserves the encoding of the given buffer" do
    buffer = ''.encode(Encoding::ISO_8859_1)

    @client.send("foobar", 0)
    sock = @server.accept
    sock.recvfrom(6, 0, buffer)
    sock.close

    buffer.encoding.should == Encoding::ISO_8859_1
  end

  platform_is_not :windows do
    it "uses different message options" do
      @client.send("foobar", Socket::MSG_PEEK)
      sock = @server.accept
      peek_data = sock.recvfrom(6, Socket::MSG_PEEK) # Does not retrieve the message
      real_data = sock.recvfrom(6)

      real_data.should == peek_data
      peek_data.should == ["foobar", ["AF_UNIX", ""]]
      sock.close
    end
  end
end

describe 'UNIXSocket#recvfrom' do
  describe 'using a socket pair' do
    before do
      @client, @server = UNIXSocket.socketpair
      @client.write('hello')
    end

    after do
      @client.close
      @server.close
    end

    platform_is_not :windows do
      it 'returns an Array containing the data and address information' do
        @server.recvfrom(5).should == ['hello', ['AF_UNIX', '']]
      end
    end

    guard -> { platform_is :windows and ruby_bug "#21702", ""..."4.2" } do
      it 'returns an Array containing the data and address information' do
        @server.recvfrom(5).should == ['hello', ['AF_UNIX', '']]
      end
    end
  end

  platform_is_not :windows do
    # These specs are taken from the rdoc examples on UNIXSocket#recvfrom.
    describe 'using a UNIX socket constructed using UNIXSocket.for_fd' do
      before do
        @path1 = SocketSpecs.socket_path
        @path2 = SocketSpecs.socket_path.chop + '2'
        rm_r(@path2)

        @client_raw = Socket.new(:UNIX, :DGRAM)
        @client_raw.bind(Socket.sockaddr_un(@path1))

        @server_raw = Socket.new(:UNIX, :DGRAM)
        @server_raw.bind(Socket.sockaddr_un(@path2))

        @socket = UNIXSocket.for_fd(@server_raw.fileno)
        @socket.autoclose = false
      end

      after do
        @client_raw.close
        @server_raw.close # also closes @socket

        rm_r @path1
        rm_r @path2
      end

      it 'returns an Array containing the data and address information' do
        @client_raw.send('hello', 0, Socket.sockaddr_un(@path2))

        @socket.recvfrom(5).should == ['hello', ['AF_UNIX', @path1]]
      end
    end
  end
end
