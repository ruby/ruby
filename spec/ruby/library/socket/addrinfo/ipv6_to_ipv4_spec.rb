require_relative '../spec_helper'
require_relative '../fixtures/classes'

guard -> { SocketSpecs.ipv6_available? } do
  describe 'Addrinfo#ipv6_to_ipv4' do
    it 'returns an Addrinfo for ::192.168.1.1' do
      addr = Addrinfo.ip('::192.168.1.1').ipv6_to_ipv4

      addr.should be_an_instance_of(Addrinfo)

      addr.afamily.should    == Socket::AF_INET
      addr.ip_address.should == '192.168.1.1'
    end

    platform_is_not :aix do
      it 'returns an Addrinfo for ::0.0.1.1' do
        addr = Addrinfo.ip('::0.0.1.1').ipv6_to_ipv4

        addr.should be_an_instance_of(Addrinfo)

        addr.afamily.should    == Socket::AF_INET
        addr.ip_address.should == '0.0.1.1'
      end

      it 'returns an Addrinfo for ::0.0.1.0' do
        addr = Addrinfo.ip('::0.0.1.0').ipv6_to_ipv4

        addr.should be_an_instance_of(Addrinfo)

        addr.afamily.should    == Socket::AF_INET
        addr.ip_address.should == '0.0.1.0'
      end

      it 'returns an Addrinfo for ::0.1.0.0' do
        addr = Addrinfo.ip('::0.1.0.0').ipv6_to_ipv4

        addr.should be_an_instance_of(Addrinfo)

        addr.afamily.should    == Socket::AF_INET
        addr.ip_address.should == '0.1.0.0'
      end
    end

    it 'returns an Addrinfo for ::ffff:192.168.1.1' do
      addr = Addrinfo.ip('::ffff:192.168.1.1').ipv6_to_ipv4

      addr.should be_an_instance_of(Addrinfo)

      addr.afamily.should    == Socket::AF_INET
      addr.ip_address.should == '192.168.1.1'
    end

    it 'returns nil for ::0.0.0.1' do
      Addrinfo.ip('::0.0.0.1').ipv6_to_ipv4.should be_nil
    end

    it 'returns nil for a pure IPv6 Addrinfo' do
      Addrinfo.ip('::1').ipv6_to_ipv4.should be_nil
    end

    it 'returns nil for an IPv4 Addrinfo' do
      Addrinfo.ip('192.168.1.1').ipv6_to_ipv4.should be_nil
    end

    with_feature :unix_socket do
      it 'returns nil for a UNIX Addrinfo' do
        Addrinfo.unix('foo').ipv6_to_ipv4.should be_nil
      end
    end
  end
end
