require_relative '../spec_helper'

describe "Addrinfo#ipv4_private?" do
  describe "for an ipv4 socket" do
    before :each do
      @private = Addrinfo.tcp("10.0.0.1", 80)
      @other   = Addrinfo.tcp("0.0.0.0", 80)
    end

    it "returns true for a private address" do
      Addrinfo.ip('10.0.0.0').should.ipv4_private?
      Addrinfo.ip('10.0.0.5').should.ipv4_private?

      Addrinfo.ip('172.16.0.0').should.ipv4_private?
      Addrinfo.ip('172.16.0.5').should.ipv4_private?

      Addrinfo.ip('192.168.0.0').should.ipv4_private?
      Addrinfo.ip('192.168.0.5').should.ipv4_private?
    end

    it "returns false for a public address" do
      @other.ipv4_private?.should be_false
    end
  end

  describe "for an ipv6 socket" do
    before :each do
      @other    = Addrinfo.tcp("::", 80)
    end

    it "returns false" do
      @other.ipv4_private?.should be_false
    end
  end

  with_feature :unix_socket do
    describe "for a unix socket" do
      before :each do
        @addrinfo = Addrinfo.unix("/tmp/sock")
      end

      it "returns false" do
        @addrinfo.ipv4_private?.should be_false
      end
    end
  end
end
