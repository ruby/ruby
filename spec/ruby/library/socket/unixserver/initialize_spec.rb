require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'UNIXServer#initialize' do
  before do
    @path = SocketSpecs.socket_path
    @server = UNIXServer.new(@path)
  end

  after do
    @server.close if @server
    rm_r @path
  end

  it 'returns a new UNIXServer' do
    @server.should.instance_of?(UNIXServer)
  end

  it 'sets the socket to binmode' do
    @server.binmode?.should == true
  end

  it 'raises Errno::EADDRINUSE when the socket is already in use' do
    -> { UNIXServer.new(@path) }.should.raise(Errno::EADDRINUSE)
  end
end
