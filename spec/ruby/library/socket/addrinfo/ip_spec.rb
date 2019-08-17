require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Addrinfo#ip?" do
  describe "for an ipv4 socket" do
    before :each do
      @addrinfo = Addrinfo.tcp("127.0.0.1", 80)
    end

    it "returns true" do
      @addrinfo.ip?.should be_true
    end
  end

  describe "for an ipv6 socket" do
    before :each do
      @addrinfo = Addrinfo.tcp("::1", 80)
    end

    it "returns true" do
      @addrinfo.ip?.should be_true
    end
  end

  with_feature :unix_socket do
    describe "for a unix socket" do
      before :each do
        @addrinfo = Addrinfo.unix("/tmp/sock")
      end

      it "returns false" do
        @addrinfo.ip?.should be_false
      end
    end
  end
end

describe 'Addrinfo.ip' do
  SocketSpecs.each_ip_protocol do |family, ip_address|
    it 'returns an Addrinfo instance' do
      Addrinfo.ip(ip_address).should be_an_instance_of(Addrinfo)
    end

    it 'sets the IP address' do
      Addrinfo.ip(ip_address).ip_address.should == ip_address
    end

    it 'sets the port to 0' do
      Addrinfo.ip(ip_address).ip_port.should == 0
    end

    it 'sets the address family' do
      Addrinfo.ip(ip_address).afamily.should == family
    end

    it 'sets the protocol family' do
      Addrinfo.ip(ip_address).pfamily.should == family
    end

    it 'sets the socket type to 0' do
      Addrinfo.ip(ip_address).socktype.should == 0
    end
  end
end
