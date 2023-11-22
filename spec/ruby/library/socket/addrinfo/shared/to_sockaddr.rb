describe :socket_addrinfo_to_sockaddr, shared: true do
  describe "for an ipv4 socket" do
    before :each do
      @addrinfo = Addrinfo.tcp("127.0.0.1", 80)
    end

    it "returns a sockaddr packed structure" do
      @addrinfo.send(@method).should == Socket.sockaddr_in(80, '127.0.0.1')
    end
  end

  describe "for an ipv6 socket" do
    before :each do
      @addrinfo = Addrinfo.tcp("::1", 80)
    end

    it "returns a sockaddr packed structure" do
      @addrinfo.send(@method).should == Socket.sockaddr_in(80, '::1')
    end
  end

  with_feature :unix_socket do
    describe "for a unix socket" do
      before :each do
        @addrinfo = Addrinfo.unix("/tmp/sock")
      end

      it "returns a sockaddr packed structure" do
        @addrinfo.send(@method).should == Socket.sockaddr_un('/tmp/sock')
      end
    end
  end

  describe 'using a Addrinfo with just an IP address' do
    it 'returns a String' do
      addr = Addrinfo.ip('127.0.0.1')

      addr.send(@method).should == Socket.sockaddr_in(0, '127.0.0.1')
    end
  end

  describe 'using a Addrinfo without an IP and port' do
    it 'returns a String' do
      addr = Addrinfo.new(['AF_INET', 0, '', ''])

      addr.send(@method).should == Socket.sockaddr_in(0, '')
    end
  end
end
