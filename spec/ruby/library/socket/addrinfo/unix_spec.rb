require_relative '../spec_helper'

with_feature :unix_socket do
  describe 'Addrinfo.unix' do
    it 'returns an Addrinfo instance' do
      Addrinfo.unix('socket').should be_an_instance_of(Addrinfo)
    end

    it 'sets the IP address' do
      Addrinfo.unix('socket').unix_path.should == 'socket'
    end

    it 'sets the address family' do
      Addrinfo.unix('socket').afamily.should == Socket::AF_UNIX
    end

    it 'sets the protocol family' do
      Addrinfo.unix('socket').pfamily.should == Socket::PF_UNIX
    end

    it 'sets the socket type' do
      Addrinfo.unix('socket').socktype.should == Socket::SOCK_STREAM
    end

    it 'sets a custom socket type' do
      addr = Addrinfo.unix('socket', Socket::SOCK_DGRAM)

      addr.socktype.should == Socket::SOCK_DGRAM
    end

    it 'sets the socket protocol to 0' do
      Addrinfo.unix('socket').protocol.should == 0
    end
  end
end

describe "Addrinfo#unix?" do
  describe "for an ipv4 socket" do

    before :each do
      @addrinfo = Addrinfo.tcp("127.0.0.1", 80)
    end

    it "returns false" do
      @addrinfo.unix?.should be_false
    end

  end

  describe "for an ipv6 socket" do
    before :each do
      @addrinfo = Addrinfo.tcp("::1", 80)
    end

    it "returns false" do
      @addrinfo.unix?.should be_false
    end
  end

  platform_is_not :windows do
    describe "for a unix socket" do
      before :each do
        @addrinfo = Addrinfo.unix("/tmp/sock")
      end

      it "returns true" do
        @addrinfo.unix?.should be_true
      end
    end
  end
end
