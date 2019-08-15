require_relative '../spec_helper'

with_feature :ancillary_data do
  describe 'Socket::AncillaryData#initialize' do
    describe 'using Integers for the family, level, and type' do
      before do
        @data = Socket::AncillaryData
          .new(Socket::AF_INET, Socket::IPPROTO_IP, Socket::IP_RECVTTL, 'ugh')
      end

      it 'sets the address family' do
        @data.family.should == Socket::AF_INET
      end

      it 'sets the message level' do
        @data.level.should == Socket::IPPROTO_IP
      end

      it 'sets the message type' do
        @data.type.should == Socket::IP_RECVTTL
      end

      it 'sets the data' do
        @data.data.should == 'ugh'
      end
    end

    describe 'using Symbols for the family, level, and type' do
      before do
        @data = Socket::AncillaryData.new(:INET, :IPPROTO_IP, :RECVTTL, 'ugh')
      end

      it 'sets the address family' do
        @data.family.should == Socket::AF_INET
      end

      it 'sets the message level' do
        @data.level.should == Socket::IPPROTO_IP
      end

      it 'sets the message type' do
        @data.type.should == Socket::IP_RECVTTL
      end

      it 'sets the data' do
        @data.data.should == 'ugh'
      end
    end

    describe 'using Strings for the family, level, and type' do
      before do
        @data = Socket::AncillaryData.new('INET', 'IPPROTO_IP', 'RECVTTL', 'ugh')
      end

      it 'sets the address family' do
        @data.family.should == Socket::AF_INET
      end

      it 'sets the message level' do
        @data.level.should == Socket::IPPROTO_IP
      end

      it 'sets the message type' do
        @data.type.should == Socket::IP_RECVTTL
      end

      it 'sets the data' do
        @data.data.should == 'ugh'
      end
    end

    describe 'using custom objects with a to_str method for the family, level, and type' do
      before do
        fmock = mock(:family)
        lmock = mock(:level)
        tmock = mock(:type)
        dmock = mock(:data)

        fmock.stub!(:to_str).and_return('INET')
        lmock.stub!(:to_str).and_return('IP')
        tmock.stub!(:to_str).and_return('RECVTTL')
        dmock.stub!(:to_str).and_return('ugh')

        @data = Socket::AncillaryData.new(fmock, lmock, tmock, dmock)
      end

      it 'sets the address family' do
        @data.family.should == Socket::AF_INET
      end

      it 'sets the message level' do
        @data.level.should == Socket::IPPROTO_IP
      end

      it 'sets the message type' do
        @data.type.should == Socket::IP_RECVTTL
      end

      it 'sets the data' do
        @data.data.should == 'ugh'
      end
    end

    describe 'using :AF_INET as the family and :SOCKET as the level' do
      it 'sets the type to SCM_RIGHTS when using :RIGHTS as the type argument' do
        Socket::AncillaryData.new(:INET, :SOCKET, :RIGHTS, '').type.should == Socket::SCM_RIGHTS
      end

      platform_is_not :"solaris2.10", :aix do
        it 'sets the type to SCM_TIMESTAMP when using :TIMESTAMP as the type argument' do
          Socket::AncillaryData.new(:INET, :SOCKET, :TIMESTAMP, '').type.should == Socket::SCM_TIMESTAMP
        end
      end

      it 'raises TypeError when using a numeric string as the type argument' do
        -> {
          Socket::AncillaryData.new(:INET, :IGMP, Socket::SCM_RIGHTS.to_s, '')
        }.should raise_error(TypeError)
      end

      it 'raises SocketError when using :RECVTTL as the type argument' do
        -> {
          Socket::AncillaryData.new(:INET, :SOCKET, :RECVTTL, '')
        }.should raise_error(SocketError)
      end

      it 'raises SocketError when using :MOO as the type argument' do
        -> {
          Socket::AncillaryData.new(:INET, :SOCKET, :MOO, '')
        }.should raise_error(SocketError)
      end

      it 'raises SocketError when using :IP_RECVTTL as the type argument' do
        -> {
          Socket::AncillaryData.new(:INET, :SOCKET, :IP_RECVTTL, '')
        }.should raise_error(SocketError)
      end
    end

    describe 'using :AF_INET as the family and :SOCKET as the level' do
      it 'sets the type to SCM_RIGHTS when using :RIGHTS as the type argument' do
        Socket::AncillaryData.new(:INET, :SOCKET, :RIGHTS, '').type.should == Socket::SCM_RIGHTS
      end
    end

    describe 'using :AF_INET as the family and :IP as the level' do
      it 'sets the type to IP_RECVTTL when using :RECVTTL as the type argument' do
        Socket::AncillaryData.new(:INET, :IP, :RECVTTL, '').type.should == Socket::IP_RECVTTL
      end

      with_feature :ip_mtu do
        it 'sets the type to IP_MTU when using :MTU as the type argument' do
          Socket::AncillaryData.new(:INET, :IP, :MTU, '').type.should == Socket::IP_MTU
        end
      end

      it 'raises SocketError when using :RIGHTS as the type argument' do
        -> {
          Socket::AncillaryData.new(:INET, :IP, :RIGHTS, '')
        }.should raise_error(SocketError)
      end

      it 'raises SocketError when using :MOO as the type argument' do
        -> {
          Socket::AncillaryData.new(:INET, :IP, :MOO, '')
        }.should raise_error(SocketError)
      end
    end

    describe 'using :AF_INET as the family and :IPV6 as the level' do
      it 'sets the type to IPV6_CHECKSUM when using :CHECKSUM as the type argument' do
        Socket::AncillaryData.new(:INET, :IPV6, :CHECKSUM, '').type.should == Socket::IPV6_CHECKSUM
      end

      with_feature :ipv6_nexthop do
        it 'sets the type to IPV6_NEXTHOP when using :NEXTHOP as the type argument' do
          Socket::AncillaryData.new(:INET, :IPV6, :NEXTHOP, '').type.should == Socket::IPV6_NEXTHOP
        end
      end

      it 'raises SocketError when using :RIGHTS as the type argument' do
        -> {
          Socket::AncillaryData.new(:INET, :IPV6, :RIGHTS, '')
        }.should raise_error(SocketError)
      end

      it 'raises SocketError when using :MOO as the type argument' do
        -> {
          Socket::AncillaryData.new(:INET, :IPV6, :MOO, '')
        }.should raise_error(SocketError)
      end
    end

    describe 'using :AF_INET as the family and :TCP as the level' do
      with_feature :tcp_cork do
        it 'sets the type to TCP_CORK when using :CORK as the type argument' do
          Socket::AncillaryData.new(:INET, :TCP, :CORK, '').type.should == Socket::TCP_CORK
        end
      end

      with_feature :tcp_info do
        it 'sets the type to TCP_INFO when using :INFO as the type argument' do
          Socket::AncillaryData.new(:INET, :TCP, :INFO, '').type.should == Socket::TCP_INFO
        end
      end

      it 'raises SocketError when using :RIGHTS as the type argument' do
        -> {
          Socket::AncillaryData.new(:INET, :TCP, :RIGHTS, '')
        }.should raise_error(SocketError)
      end

      it 'raises SocketError when using :MOO as the type argument' do
        -> {
          Socket::AncillaryData.new(:INET, :TCP, :MOO, '')
        }.should raise_error(SocketError)
      end
    end

    describe 'using :AF_INET as the family and :UDP as the level' do
      with_feature :udp_cork do
        it 'sets the type to UDP_CORK when using :CORK as the type argument' do
          Socket::AncillaryData.new(:INET, :UDP, :CORK, '').type.should == Socket::UDP_CORK
        end
      end

      it 'raises SocketError when using :RIGHTS as the type argument' do
        -> {
          Socket::AncillaryData.new(:INET, :UDP, :RIGHTS, '')
        }.should raise_error(SocketError)
      end

      it 'raises SocketError when using :MOO as the type argument' do
        -> {
          Socket::AncillaryData.new(:INET, :UDP, :MOO, '')
        }.should raise_error(SocketError)
      end
    end

    describe 'using :AF_UNIX as the family and :SOCKET as the level' do
      it 'sets the type to SCM_RIGHTS when using :RIGHTS as the type argument' do
        Socket::AncillaryData.new(:UNIX, :SOCKET, :RIGHTS, '').type.should == Socket::SCM_RIGHTS
      end

      it 'raises SocketError when using :CORK sa the type argument' do
        -> {
          Socket::AncillaryData.new(:UNIX, :SOCKET, :CORK, '')
        }.should raise_error(SocketError)
      end
    end

    describe 'using :AF_UNIX as the family and :IP as the level' do
      it 'raises SocketError' do
        -> {
          Socket::AncillaryData.new(:UNIX, :IP, :RECVTTL, '')
        }.should raise_error(SocketError)
      end
    end

    describe 'using :AF_UNIX as the family and :IPV6 as the level' do
      it 'raises SocketError' do
        -> {
          Socket::AncillaryData.new(:UNIX, :IPV6, :NEXTHOP, '')
        }.should raise_error(SocketError)
      end
    end

    describe 'using :AF_UNIX as the family and :TCP as the level' do
      it 'raises SocketError' do
        -> {
          Socket::AncillaryData.new(:UNIX, :TCP, :CORK, '')
        }.should raise_error(SocketError)
      end
    end

    describe 'using :AF_UNIX as the family and :UDP as the level' do
      it 'raises SocketError' do
        -> {
          Socket::AncillaryData.new(:UNIX, :UDP, :CORK, '')
        }.should raise_error(SocketError)
      end
    end
  end
end
