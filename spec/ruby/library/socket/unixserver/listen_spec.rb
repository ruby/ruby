require_relative '../spec_helper'
require_relative '../fixtures/classes'

with_feature :unix_socket do
  describe 'UNIXServer#listen' do
    before do
      @path   = SocketSpecs.socket_path
      @server = UNIXServer.new(@path)
    end

    after do
      @server.close

      rm_r(@path)
    end

    it 'returns 0' do
      @server.listen(1).should == 0
    end
  end
end
