require_relative '../spec_helper'

describe 'Addrinfo#listen' do
  before do
    @addr   = Addrinfo.tcp('127.0.0.1', 0)
    @socket = nil
  end

  after do
    @socket.close if @socket
  end

  it 'returns a Socket when no block is given' do
    @socket = @addr.listen

    @socket.should be_an_instance_of(Socket)
  end

  it 'yields the Socket if a block is given' do
    @addr.listen do |socket|
      socket.should be_an_instance_of(Socket)
    end
  end

  it 'closes the socket if a block is given' do
    socket = nil

    @addr.listen do |sock|
      socket = sock
    end

    socket.should.closed?
  end
end
