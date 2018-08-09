require_relative '../spec_helper'

describe 'Socket.udp_server_recv' do
  before do
    @server = Socket.new(:INET, :DGRAM)
    @client = Socket.new(:INET, :DGRAM)

    @server.bind(Socket.sockaddr_in(0, '127.0.0.1'))
    @client.connect(@server.getsockname)
  end

  after do
    @client.close
    @server.close
  end

  it 'yields the message and a Socket::UDPSource' do
    msg = nil
    src = nil

    @client.write('hello')

    # FreeBSD sockets are not instanteous over loopback and
    # will EAGAIN on recv.
    platform_is :darwin, :freebsd do
      IO.select([@server])
    end

    Socket.udp_server_recv([@server]) do |message, source|
      msg = message
      src = source
      break
    end

    msg.should == 'hello'
    src.should be_an_instance_of(Socket::UDPSource)
  end
end
