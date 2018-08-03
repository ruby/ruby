require_relative '../spec_helper'


describe 'Addrinfo#inspect_sockaddr' do
  describe 'using an IPv4 address' do
    it 'returns a String containing the IP address and port number' do
      addr = Addrinfo.tcp('127.0.0.1', 80)

      addr.inspect_sockaddr.should == '127.0.0.1:80'
    end

    it 'returns a String containing just the IP address when no port is given' do
      addr = Addrinfo.tcp('127.0.0.1', 0)

      addr.inspect_sockaddr.should == '127.0.0.1'
    end
  end

  describe 'using an IPv6 address' do
    before :each do
      @ip = '2001:0db8:85a3:0000:0000:8a2e:0370:7334'
    end

    it 'returns a String containing the IP address and port number' do
      Addrinfo.tcp('::1', 80).inspect_sockaddr.should == '[::1]:80'
      Addrinfo.tcp(@ip, 80).inspect_sockaddr.should == '[2001:db8:85a3::8a2e:370:7334]:80'
    end

    it 'returns a String containing just the IP address when no port is given' do
      Addrinfo.tcp('::1', 0).inspect_sockaddr.should == '::1'
      Addrinfo.tcp(@ip, 0).inspect_sockaddr.should == '2001:db8:85a3::8a2e:370:7334'
    end
  end

  with_feature :unix_socket do
    describe 'using a UNIX path' do
      it 'returns a String containing the UNIX path' do
        addr = Addrinfo.unix('/foo/bar')

        addr.inspect_sockaddr.should == '/foo/bar'
      end

      it 'returns a String containing the UNIX path when using a relative path' do
        addr = Addrinfo.unix('foo')

        addr.inspect_sockaddr.should == 'UNIX foo'
      end
    end
  end
end
