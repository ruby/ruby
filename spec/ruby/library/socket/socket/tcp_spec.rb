require_relative '../spec_helper'

describe 'Socket.tcp' do
  before do
    @server = Socket.new(:INET, :STREAM)
    @client = nil

    @server.bind(Socket.sockaddr_in(0, '127.0.0.1'))
    @server.listen(1)

    @host = @server.connect_address.ip_address
    @port = @server.connect_address.ip_port
  end

  after do
    @client.close if @client && !@client.closed?
    @client = nil

    @server.close
  end

  it 'returns a Socket when no block is given' do
    @client = Socket.tcp(@host, @port)

    @client.should.instance_of?(Socket)
  end

  it 'yields the Socket when a block is given' do
    Socket.tcp(@host, @port) do |socket|
      socket.should.instance_of?(Socket)
    end
  end

  it 'closes the Socket automatically when a block is given' do
    Socket.tcp(@host, @port) do |socket|
      @socket = socket
    end

    @socket.should.closed?
  end

  it 'binds to a local address and port when specified' do
    @client = Socket.tcp(@host, @port, @host, 0)

    @client.local_address.ip_address.should == @host

    @client.local_address.ip_port.should > 0
    @client.local_address.ip_port.should_not == @port
  end

  it 'raises ArgumentError when 6 arguments are provided' do
    -> {
      Socket.tcp(@host, @port, @host, 0, {:connect_timeout => 1}, 10)
    }.should.raise(ArgumentError)
  end

  it 'connects to the server' do
    @client = Socket.tcp(@host, @port)
    @client.write('hello')
    connection, _ = @server.accept
    begin
      connection.recv(5).should == 'hello'
    ensure
      connection.close
    end
  end

  ruby_version_is "4.0" do
    it 'connects to the server when passed open_timeout argument' do
      @client = Socket.tcp(@host, @port, open_timeout: 60)
      @client.write('open_timeout')
      connection, _ = @server.accept
      begin
        connection.recv(12).should == 'open_timeout'
      ensure
        connection.close
      end
    end

    it 'raises Errno::ETIMEDOUT with :open_timeout when no server is listening on the given address' do
      -> {
        Socket.tcp("192.0.2.1", 80, open_timeout: 0)
      }.should.raise(Errno::ETIMEDOUT)
    rescue Errno::ENETUNREACH
      skip "all network interfaces down"
    end
  end
end

platform_is_not :windows do
  guard -> {
    begin
      !Socket.getaddrinfo('localhost', nil, Socket::AF_INET).empty? &&
        !Socket.getaddrinfo('localhost', nil, Socket::AF_INET6).empty?
    rescue SocketError
      false
    end
  } do
    describe 'Socket.tcp' do
      describe 'when the hostname resolves to both an IPv6 and an IPv4 address' do
        before do
          @server = TCPServer.new('127.0.0.1', 0)
          @port = @server.addr[1]
          @client = nil
        end

        after do
          @client.close if @client && !@client.closed?
          @server.close
        end

        it 'connects over IPv4 when only the IPv4 address is listening' do
          @client = Socket.tcp('localhost', @port, connect_timeout: 10)

          @client.remote_address.ip_address.should == '127.0.0.1'
          @client.write('hello').should == 5

          connection = @server.accept
          begin
            connection.read(5).should == 'hello'
          ensure
            connection.close
          end
        end
      end
    end
  end
end
