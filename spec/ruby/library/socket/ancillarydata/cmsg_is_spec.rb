require_relative '../spec_helper'

with_feature :ancillary_data do
  describe 'Socket::AncillaryData#cmsg_is?' do
    describe 'using :INET, :IP, :TTL as the family, level, and type' do
      before do
        @data = Socket::AncillaryData.new(:INET, :IP, :TTL, '')
      end

      it 'returns true when comparing with IPPROTO_IP and IP_TTL' do
        @data.cmsg_is?(Socket::IPPROTO_IP, Socket::IP_TTL).should == true
      end

      it 'returns true when comparing with :IP and :TTL' do
        @data.cmsg_is?(:IP, :TTL).should == true
      end

      with_feature :pktinfo do
        it 'returns false when comparing with :IP and :PKTINFO' do
          @data.cmsg_is?(:IP, :PKTINFO).should == false
        end
      end

      it 'returns false when comparing with :SOCKET and :RIGHTS' do
        @data.cmsg_is?(:SOCKET, :RIGHTS).should == false
      end

      it 'raises SocketError when comparign with :IPV6 and :RIGHTS' do
        lambda { @data.cmsg_is?(:IPV6, :RIGHTS) }.should raise_error(SocketError)
      end
    end
  end
end
