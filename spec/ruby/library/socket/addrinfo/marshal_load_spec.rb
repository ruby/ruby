require_relative '../spec_helper'

describe 'Addrinfo#marshal_load' do
  describe 'using an IP address' do
    it 'returns a new Addrinfo' do
      source = Addrinfo.getaddrinfo('localhost', 80, :INET, :STREAM,
                                    Socket::IPPROTO_TCP, Socket::AI_CANONNAME)[0]

      addr = Marshal.load(Marshal.dump(source))

      addr.afamily.should    == source.afamily
      addr.pfamily.should    == source.pfamily
      addr.socktype.should   == source.socktype
      addr.protocol.should   == source.protocol
      addr.ip_address.should == source.ip_address
      addr.ip_port.should    == source.ip_port
      addr.canonname.should  == source.canonname
    end
  end

  with_feature :unix_socket do
    describe 'using a UNIX socket' do
      it 'returns a new Addrinfo' do
        source = Addrinfo.unix('foo')
        addr   = Marshal.load(Marshal.dump(source))

        addr.afamily.should   == source.afamily
        addr.pfamily.should   == source.pfamily
        addr.socktype.should  == source.socktype
        addr.protocol.should  == source.protocol
        addr.unix_path.should == source.unix_path
      end
    end
  end
end
