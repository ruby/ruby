require_relative '../spec_helper'

describe 'Addrinfo#inspect' do
  describe 'using an IPv4 Addrinfo' do
    it 'returns a String when using a TCP Addrinfo' do
      addr = Addrinfo.tcp('127.0.0.1', 80)

      addr.inspect.should == '#<Addrinfo: 127.0.0.1:80 TCP>'
    end

    it 'returns a String when using an UDP Addrinfo' do
      addr = Addrinfo.udp('127.0.0.1', 80)

      addr.inspect.should == '#<Addrinfo: 127.0.0.1:80 UDP>'
    end

    it 'returns a String when using an Addrinfo without a port' do
      addr = Addrinfo.ip('127.0.0.1')

      addr.inspect.should == '#<Addrinfo: 127.0.0.1>'
    end
  end

  describe 'using an IPv6 Addrinfo' do
    it 'returns a String when using a TCP Addrinfo' do
      addr = Addrinfo.tcp('::1', 80)

      addr.inspect.should == '#<Addrinfo: [::1]:80 TCP>'
    end

    it 'returns a String when using an UDP Addrinfo' do
      addr = Addrinfo.udp('::1', 80)

      addr.inspect.should == '#<Addrinfo: [::1]:80 UDP>'
    end

    it 'returns a String when using an Addrinfo without a port' do
      addr = Addrinfo.ip('::1')

      addr.inspect.should == '#<Addrinfo: ::1>'
    end
  end

  with_feature :unix_socket do
    describe 'using a UNIX Addrinfo' do
      it 'returns a String' do
        addr = Addrinfo.unix('/foo')

        addr.inspect.should == '#<Addrinfo: /foo SOCK_STREAM>'
      end

      it 'returns a String when using a relative UNIX path' do
        addr = Addrinfo.unix('foo')

        addr.inspect.should == '#<Addrinfo: UNIX foo SOCK_STREAM>'
      end

      it 'returns a String when using a DGRAM socket' do
        addr = Addrinfo.unix('/foo', Socket::SOCK_DGRAM)

        addr.inspect.should == '#<Addrinfo: /foo SOCK_DGRAM>'
      end
    end
  end
end
