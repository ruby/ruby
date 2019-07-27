require_relative '../spec_helper'

with_feature :unix_socket do
  describe "Addrinfo#unix_path" do
    describe "for an ipv4 socket" do

      before :each do
        @addrinfo = Addrinfo.tcp("127.0.0.1", 80)
      end

      it "raises an exception" do
        -> { @addrinfo.unix_path }.should raise_error(SocketError)
      end

    end

    describe "for an ipv6 socket" do
      before :each do
        @addrinfo = Addrinfo.tcp("::1", 80)
      end

      it "raises an exception" do
        -> { @addrinfo.unix_path }.should raise_error(SocketError)
      end
    end

    describe "for a unix socket" do
      before :each do
        @addrinfo = Addrinfo.unix("/tmp/sock")
      end

      it "returns the socket path" do
        @addrinfo.unix_path.should == "/tmp/sock"
      end
    end
  end
end
