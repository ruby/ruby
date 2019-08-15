require_relative '../spec_helper'

with_feature :ancillary_data, :ipv6_pktinfo do
  describe 'Socket::AncillaryData.ipv6_pktinfo' do
    before do
      @data = Socket::AncillaryData.ipv6_pktinfo(Addrinfo.ip('::1'), 4)
    end

    it 'returns a Socket::AncillaryData' do
      @data.should be_an_instance_of(Socket::AncillaryData)
    end

    it 'sets the family to AF_INET' do
      @data.family.should == Socket::AF_INET6
    end

    it 'sets the level to IPPROTO_IP' do
      @data.level.should == Socket::IPPROTO_IPV6
    end

    it 'sets the type to IP_PKTINFO' do
      @data.type.should == Socket::IPV6_PKTINFO
    end
  end

  describe 'Socket::AncillaryData#ipv6_pktinfo' do
    describe 'using an Addrinfo without a port number' do
      before do
        @source = Addrinfo.ip('::1')
        @data   = Socket::AncillaryData.ipv6_pktinfo(@source, 4)
      end

      it 'returns an Array' do
        @data.ipv6_pktinfo.should be_an_instance_of(Array)
      end

      describe 'the returned Array' do
        before do
          @info = @data.ipv6_pktinfo
        end

        it 'stores an Addrinfo at index 0' do
          @info[0].should be_an_instance_of(Addrinfo)
        end

        it 'stores the ifindex at index 1' do
          @info[1].should be_kind_of(Integer)
        end
      end

      describe 'the source Addrinfo' do
        before do
          @addr = @data.ipv6_pktinfo[0]
        end

        it 'uses the correct IP address' do
          @addr.ip_address.should == '::1'
        end

        it 'is not the same object as the input Addrinfo' do
          @addr.should_not equal @source
        end
      end

      describe 'the ifindex' do
        it 'is an Integer' do
          @data.ipv6_pktinfo[1].should == 4
        end
      end
    end

    describe 'using an Addrinfo with a port number' do
      before do
        @source = Addrinfo.tcp('::1', 80)
        @data   = Socket::AncillaryData.ipv6_pktinfo(@source, 4)
      end

      describe 'the source Addrinfo' do
        before do
          @addr = @data.ipv6_pktinfo[0]
        end

        it 'does not contain a port number' do
          @addr.ip_port.should == 0
        end
      end
    end
  end
end
