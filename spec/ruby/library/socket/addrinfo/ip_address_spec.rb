require_relative '../spec_helper'

describe "Addrinfo#ip_address" do
  describe "for an ipv4 socket" do
    before :each do
      @addrinfo = Addrinfo.tcp("127.0.0.1", 80)
    end

    it "returns the ip address" do
      @addrinfo.ip_address.should == "127.0.0.1"
    end
  end

  describe "for an ipv6 socket" do
    before :each do
      @addrinfo = Addrinfo.tcp("::1", 80)
    end

    it "returns the ip address" do
      @addrinfo.ip_address.should == "::1"
    end
  end

  with_feature :unix_socket do
    describe "for a unix socket" do
      before :each do
        @addrinfo = Addrinfo.unix("/tmp/sock")
      end

      it "raises an exception" do
        lambda { @addrinfo.ip_address }.should raise_error(SocketError)
      end
    end
  end

  describe 'with an Array as the socket address' do
    it 'returns the IP as a String' do
      sockaddr = ['AF_INET', 80, 'localhost', '127.0.0.1']
      addr     = Addrinfo.new(sockaddr)

      addr.ip_address.should == '127.0.0.1'
    end
  end

  describe 'without an IP address' do
    before do
      @ips = ['127.0.0.1', '0.0.0.0', '::1']
    end

    # Both these cases seem to return different values at times on MRI. Since
    # this is network dependent we can't rely on an exact IP being returned.
    it 'returns the local IP address when using an empty String as the IP' do
      sockaddr = Socket.sockaddr_in(80, '')
      addr     = Addrinfo.new(sockaddr)

      @ips.include?(addr.ip_address).should == true
    end

    it 'returns the local IP address when using nil as the IP' do
      sockaddr = Socket.sockaddr_in(80, nil)
      addr     = Addrinfo.new(sockaddr)

      @ips.include?(addr.ip_address).should == true
    end
  end

  # On MRI calling Addrinfo#ip_address with AF_UNSPEC as the address family is
  # supposed to raise a SocketError. MRI however doesn't provide a way to
  # actually initialize an Addrinfo with AF_UNSPEC, nor does it allow stubbing
  # of any methods since Addrinfo doesn't use any Ruby methods for checking the
  # IP address. As a result we can only run this test on Rubinius.
  with_feature :pure_ruby_addrinfo do
    describe 'with a non IPv4 or IPv6 address' do
      it 'raises SocketError' do
        sockaddr = Socket.sockaddr_in(80, '127.0.0.1')
        addr     = Addrinfo.new(sockaddr)

        addr.stub!(:ipv4?).and_return(false)
        addr.stub!(:ipv6?).and_return(false)

        lambda { addr.ip_address }.should raise_error(SocketError)
      end
    end
  end
end
