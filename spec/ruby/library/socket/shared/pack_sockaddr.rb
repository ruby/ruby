# coding: utf-8
describe :socket_pack_sockaddr_in, shared: true do
  it "packs and unpacks" do
    sockaddr_in = Socket.public_send(@method, 0, nil)
    port, addr = Socket.unpack_sockaddr_in(sockaddr_in)
    ["127.0.0.1", "::1"].include?(addr).should == true
    port.should == 0

    sockaddr_in = Socket.public_send(@method, 0, '')
    Socket.unpack_sockaddr_in(sockaddr_in).should == [0, '0.0.0.0']

    sockaddr_in = Socket.public_send(@method, 80, '127.0.0.1')
    Socket.unpack_sockaddr_in(sockaddr_in).should == [80, '127.0.0.1']

    sockaddr_in = Socket.public_send(@method, '80', '127.0.0.1')
    Socket.unpack_sockaddr_in(sockaddr_in).should == [80, '127.0.0.1']

    sockaddr_in = Socket.public_send(@method, nil, '127.0.0.1')
    Socket.unpack_sockaddr_in(sockaddr_in).should == [0, '127.0.0.1']

    sockaddr_in = Socket.public_send(@method, 80, Socket::INADDR_ANY)
    Socket.unpack_sockaddr_in(sockaddr_in).should == [80, '0.0.0.0']
  end

  platform_is_not :solaris do
    it 'resolves the service name to a port' do
      sockaddr_in = Socket.public_send(@method, 'http', '127.0.0.1')
      Socket.unpack_sockaddr_in(sockaddr_in).should == [80, '127.0.0.1']
    end
  end

  describe 'using an IPv4 address' do
    it 'returns a String of 16 bytes' do
      str = Socket.public_send(@method, 80, '127.0.0.1')

      str.should be_an_instance_of(String)
      str.bytesize.should == 16
    end
  end

  platform_is_not :solaris do
    describe 'using an IPv6 address' do
      it 'returns a String of 28 bytes' do
        str = Socket.public_send(@method, 80, '::1')

        str.should be_an_instance_of(String)
        str.bytesize.should == 28
      end
    end
  end

  platform_is :solaris do
    describe 'using an IPv6 address' do
      it 'returns a String of 32 bytes' do
        str = Socket.public_send(@method, 80, '::1')

        str.should be_an_instance_of(String)
        str.bytesize.should == 32
      end
    end
  end
end

describe :socket_pack_sockaddr_un, shared: true do
  with_feature :unix_socket do
    it 'should be idempotent' do
      bytes = Socket.public_send(@method, '/tmp/foo').bytes
      bytes[2..9].should == [47, 116, 109, 112, 47, 102, 111, 111]
      bytes[10..-1].all?(&:zero?).should == true
    end

    it "packs and unpacks" do
      sockaddr_un = Socket.public_send(@method, '/tmp/s')
      Socket.unpack_sockaddr_un(sockaddr_un).should == '/tmp/s'
    end

    it "handles correctly paths with multibyte chars" do
      sockaddr_un = Socket.public_send(@method, '/home/вася/sock')
      path = Socket.unpack_sockaddr_un(sockaddr_un).encode('UTF-8', 'UTF-8')
      path.should == '/home/вася/sock'
    end
  end

  platform_is :linux do
    it 'returns a String of 110 bytes' do
      str = Socket.public_send(@method, '/tmp/test.sock')

      str.should be_an_instance_of(String)
      str.bytesize.should == 110
    end
  end

  platform_is :bsd do
    it 'returns a String of 106 bytes' do
      str = Socket.public_send(@method, '/tmp/test.sock')

      str.should be_an_instance_of(String)
      str.bytesize.should == 106
    end
  end

  platform_is_not :windows, :aix do
    it "raises ArgumentError for paths that are too long" do
      # AIX doesn't raise error
      long_path = 'a' * 110
      -> { Socket.public_send(@method, long_path) }.should raise_error(ArgumentError)
    end
  end
end
