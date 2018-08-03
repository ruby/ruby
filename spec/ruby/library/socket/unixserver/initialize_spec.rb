require_relative '../spec_helper'
require_relative '../fixtures/classes'

with_feature :unix_socket do
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
      @server.should be_an_instance_of(UNIXServer)
    end

    it 'sets the socket to binmode' do
      @server.binmode?.should be_true
    end

    it 'raises Errno::EADDRINUSE when the socket is already in use' do
      lambda { UNIXServer.new(@path) }.should raise_error(Errno::EADDRINUSE)
    end
  end
end
