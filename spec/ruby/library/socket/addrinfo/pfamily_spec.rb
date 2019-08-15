require_relative '../spec_helper'

describe "Addrinfo#pfamily" do
  it 'returns PF_UNSPEC as the default socket family' do
    sockaddr = Socket.pack_sockaddr_in(80, 'localhost')

    Addrinfo.new(sockaddr).pfamily.should == Socket::PF_UNSPEC
  end

  describe "for an ipv4 socket" do

    before :each do
      @addrinfo = Addrinfo.tcp("127.0.0.1", 80)
    end

    it "returns Socket::PF_INET" do
      @addrinfo.pfamily.should == Socket::PF_INET
    end

  end

  describe "for an ipv6 socket" do
    before :each do
      @addrinfo = Addrinfo.tcp("::1", 80)
    end

    it "returns Socket::PF_INET6" do
      @addrinfo.pfamily.should == Socket::PF_INET6
    end
  end

  with_feature :unix_socket do
    describe "for a unix socket" do
      before :each do
        @addrinfo = Addrinfo.unix("/tmp/sock")
      end

      it "returns Socket::PF_UNIX" do
        @addrinfo.pfamily.should == Socket::PF_UNIX
      end
    end
  end
end
