require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket.sockaddr_un" do
  it 'should be idempotent' do
    bytes = Socket.sockaddr_un('/tmp/foo').bytes
    bytes[2..9].should == [47, 116, 109, 112, 47, 102, 111, 111]
    bytes[10..-1].all?(&:zero?).should == true
  end

  it "packs and unpacks" do
    sockaddr_un = Socket.sockaddr_un('/tmp/s')
    Socket.unpack_sockaddr_un(sockaddr_un).should == '/tmp/s'
  end

  it "handles correctly paths with multibyte chars" do
    sockaddr_un = Socket.sockaddr_un('/home/вася/sock')
    path = Socket.unpack_sockaddr_un(sockaddr_un).encode('UTF-8', 'UTF-8')
    path.should == '/home/вася/sock'
  end

  platform_is :linux do
    it 'returns a String of 110 bytes' do
      str = Socket.sockaddr_un('/tmp/test.sock')

      str.should.instance_of?(String)
      str.bytesize.should == 110
    end
  end

  platform_is :bsd do
    it 'returns a String of 106 bytes' do
      str = Socket.sockaddr_un('/tmp/test.sock')

      str.should.instance_of?(String)
      str.bytesize.should == 106
    end
  end

  platform_is_not :aix do
    it "raises ArgumentError for paths that are too long" do
      # AIX doesn't raise error
      long_path = 'a' * 110
      -> { Socket.sockaddr_un(long_path) }.should.raise(ArgumentError)
    end
  end
end
