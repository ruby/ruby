require_relative '../spec_helper'

describe "Addrinfo#afamily" do
  describe "for an ipv4 socket" do

    before :each do
      @addrinfo = Addrinfo.tcp("127.0.0.1", 80)
    end

    it "returns Socket::AF_INET" do
      @addrinfo.afamily.should == Socket::AF_INET
    end

  end

  describe "for an ipv6 socket" do
    before :each do
      @addrinfo = Addrinfo.tcp("::1", 80)
    end

    it "returns Socket::AF_INET6" do
      @addrinfo.afamily.should == Socket::AF_INET6
    end
  end

  with_feature :unix_socket do
    describe "for a unix socket" do
      before :each do
        @addrinfo = Addrinfo.unix("/tmp/sock")
      end

      it "returns Socket::AF_UNIX" do
        @addrinfo.afamily.should == Socket::AF_UNIX
      end
    end
  end
end
