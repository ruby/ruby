require_relative '../spec_helper'

describe "Addrinfo#ipv4_loopback?" do
  describe "for an ipv4 socket" do
    it "returns true for the loopback address" do
      Addrinfo.ip('127.0.0.1').ipv4_loopback?.should == true
      Addrinfo.ip('127.0.0.2').ipv4_loopback?.should == true
      Addrinfo.ip('127.255.0.1').ipv4_loopback?.should == true
      Addrinfo.ip('127.255.255.255').ipv4_loopback?.should == true
    end

    it "returns false for another address" do
      Addrinfo.ip('255.255.255.0').ipv4_loopback?.should be_false
    end
  end

  describe "for an ipv6 socket" do
    before :each do
      @loopback = Addrinfo.tcp("::1", 80)
      @other    = Addrinfo.tcp("::", 80)
    end

    it "returns false for the loopback address" do
      @loopback.ipv4_loopback?.should be_false
    end

    it "returns false for another address" do
      @other.ipv4_loopback?.should be_false
    end
  end

  with_feature :unix_socket do
    describe "for a unix socket" do
      before :each do
        @addrinfo = Addrinfo.unix("/tmp/sock")
      end

      it "returns false" do
        @addrinfo.ipv4_loopback?.should be_false
      end
    end
  end
end
