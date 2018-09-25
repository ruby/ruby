require_relative '../spec_helper'

with_feature :ancillary_data, :pktinfo do
  describe 'Socket::AncillaryData.ip_pktinfo' do
    describe 'with a source address and index' do
      before do
        @data = Socket::AncillaryData.ip_pktinfo(Addrinfo.ip('127.0.0.1'), 4)
      end

      it 'returns a Socket::AncillaryData' do
        @data.should be_an_instance_of(Socket::AncillaryData)
      end

      it 'sets the family to AF_INET' do
        @data.family.should == Socket::AF_INET
      end

      it 'sets the level to IPPROTO_IP' do
        @data.level.should == Socket::IPPROTO_IP
      end

      it 'sets the type to IP_PKTINFO' do
        @data.type.should == Socket::IP_PKTINFO
      end
    end

    describe 'with a source address, index, and destination address' do
      before do
        source = Addrinfo.ip('127.0.0.1')
        dest   = Addrinfo.ip('127.0.0.5')
        @data  = Socket::AncillaryData.ip_pktinfo(source, 4, dest)
      end

      it 'returns a Socket::AncillaryData' do
        @data.should be_an_instance_of(Socket::AncillaryData)
      end

      it 'sets the family to AF_INET' do
        @data.family.should == Socket::AF_INET
      end

      it 'sets the level to IPPROTO_IP' do
        @data.level.should == Socket::IPPROTO_IP
      end

      it 'sets the type to IP_PKTINFO' do
        @data.type.should == Socket::IP_PKTINFO
      end
    end
  end

  describe 'Socket::AncillaryData#ip_pktinfo' do
    describe 'using an Addrinfo without a port number' do
      before do
        @source = Addrinfo.ip('127.0.0.1')
        @dest   = Addrinfo.ip('127.0.0.5')
        @data   = Socket::AncillaryData.ip_pktinfo(@source, 4, @dest)
      end

      it 'returns an Array' do
        @data.ip_pktinfo.should be_an_instance_of(Array)
      end

      describe 'the returned Array' do
        before do
          @info = @data.ip_pktinfo
        end

        it 'stores an Addrinfo at index 0' do
          @info[0].should be_an_instance_of(Addrinfo)
        end

        it 'stores the ifindex at index 1' do
          @info[1].should be_kind_of(Integer)
        end

        it 'stores an Addrinfo at index 2' do
          @info[2].should be_an_instance_of(Addrinfo)
        end
      end

      describe 'the source Addrinfo' do
        before do
          @addr = @data.ip_pktinfo[0]
        end

        it 'uses the correct IP address' do
          @addr.ip_address.should == '127.0.0.1'
        end

        it 'is not the same object as the input Addrinfo' do
          @addr.should_not == @source
        end
      end

      describe 'the ifindex' do
        it 'is an Integer' do
          @data.ip_pktinfo[1].should == 4
        end
      end

      describe 'the destination Addrinfo' do
        before do
          @addr = @data.ip_pktinfo[2]
        end

        it 'uses the correct IP address' do
          @addr.ip_address.should == '127.0.0.5'
        end

        it 'is not the same object as the input Addrinfo' do
          @addr.should_not == @dest
        end
      end
    end

    describe 'using an Addrinfo with a port number' do
      before do
        @source = Addrinfo.tcp('127.0.0.1', 80)
        @dest   = Addrinfo.tcp('127.0.0.5', 85)
        @data   = Socket::AncillaryData.ip_pktinfo(@source, 4, @dest)
      end

      describe 'the source Addrinfo' do
        before do
          @addr = @data.ip_pktinfo[0]
        end

        it 'does not contain a port number' do
          @addr.ip_port.should == 0
        end
      end

      describe 'the destination Addrinfo' do
        before do
          @addr = @data.ip_pktinfo[2]
        end

        it 'does not contain a port number' do
          @addr.ip_port.should == 0
        end
      end
    end
  end
end
