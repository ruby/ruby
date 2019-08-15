require_relative '../spec_helper'
require_relative '../fixtures/classes'

guard -> { SocketSpecs.ipv6_available? } do
  describe 'Socket#ipv6only!' do
    before do
      @socket = Socket.new(:INET6, :DGRAM)
    end

    after do
      @socket.close
    end

    it 'enables IPv6 only mode' do
      @socket.ipv6only!

      @socket.getsockopt(:IPV6, :V6ONLY).bool.should == true
    end
  end
end
