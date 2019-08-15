require_relative '../spec_helper'

describe 'Addrinfo#marshal_dump' do
  describe 'using an IP Addrinfo' do
    before do
      @addr = Addrinfo.getaddrinfo('localhost', 80, :INET, :STREAM,
                                   Socket::IPPROTO_TCP, Socket::AI_CANONNAME)[0]
    end

    it 'returns an Array' do
      @addr.marshal_dump.should be_an_instance_of(Array)
    end

    describe 'the returned Array' do
      before do
        @array = @addr.marshal_dump
      end

      it 'includes the address family as the 1st value' do
        @array[0].should == 'AF_INET'
      end

      it 'includes the IP address as the 2nd value' do
        @array[1].should == [@addr.ip_address, @addr.ip_port.to_s]
      end

      it 'includes the protocol family as the 3rd value' do
        @array[2].should == 'PF_INET'
      end

      it 'includes the socket type as the 4th value' do
        @array[3].should == 'SOCK_STREAM'
      end

      platform_is_not :'solaris2.10' do # i386-solaris
        it 'includes the protocol as the 5th value' do
          @array[4].should == 'IPPROTO_TCP'
        end
      end

      it 'includes the canonical name as the 6th value' do
        @array[5].should == @addr.canonname
      end
    end
  end

  with_feature :unix_socket do
    describe 'using a UNIX Addrinfo' do
      before do
        @addr = Addrinfo.unix('foo')
      end

      it 'returns an Array' do
        @addr.marshal_dump.should be_an_instance_of(Array)
      end

      describe 'the returned Array' do
        before do
          @array = @addr.marshal_dump
        end

        it 'includes the address family as the 1st value' do
          @array[0].should == 'AF_UNIX'
        end

        it 'includes the UNIX path as the 2nd value' do
          @array[1].should == @addr.unix_path
        end

        it 'includes the protocol family as the 3rd value' do
          @array[2].should == 'PF_UNIX'
        end

        it 'includes the socket type as the 4th value' do
          @array[3].should == 'SOCK_STREAM'
        end

        it 'includes the protocol as the 5th value' do
          @array[4].should == 0
        end
      end
    end
  end
end
