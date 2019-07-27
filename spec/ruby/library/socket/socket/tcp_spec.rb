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

    @client.should be_an_instance_of(Socket)
  end

  it 'yields the Socket when a block is given' do
    Socket.tcp(@host, @port) do |socket|
      socket.should be_an_instance_of(Socket)
    end
  end

  it 'closes the Socket automatically when a block is given' do
    Socket.tcp(@host, @port) do |socket|
      @socket = socket
    end

    @socket.closed?.should == true
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
    }.should raise_error(ArgumentError)
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
end
