require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe 'Addrinfo#getnameinfo' do
  describe 'using an IP Addrinfo' do
    SocketSpecs.each_ip_protocol do |family, ip_address|
      before do
        @addr = Addrinfo.tcp(ip_address, 80)
      end

      it 'returns the node and service names' do
        host, service = @addr.getnameinfo

        host.should be_an_instance_of(String)
        service.should == 'http'
      end

      it 'accepts flags as a Fixnum as the first argument' do
        host, service = @addr.getnameinfo(Socket::NI_NUMERICSERV)

        host.should be_an_instance_of(String)
        service.should == '80'
      end
    end
  end

  platform_is :linux do
    with_feature :unix_socket do
      describe 'using a UNIX Addrinfo' do
        before do
          @addr = Addrinfo.unix('cats')
          @host = Socket.gethostname
        end

        it 'returns the hostname and UNIX socket path' do
          host, path = @addr.getnameinfo

          host.should == @host
          path.should == 'cats'
        end
      end
    end
  end
end
