require_relative '../spec_helper'

describe "Addrinfo#ipv6_loopback?" do
  describe "for an ipv4 socket" do
    before :each do
      @loopback = Addrinfo.tcp("127.0.0.1", 80)
      @other    = Addrinfo.tcp("0.0.0.0", 80)
    end

    it "returns false for the loopback address" do
      @loopback.ipv6_loopback?.should be_false
    end

    it "returns false for another address" do
      @other.ipv6_loopback?.should be_false
    end
  end

  describe "for an ipv6 socket" do
    before :each do
      @loopback = Addrinfo.tcp("::1", 80)
      @other    = Addrinfo.tcp("::", 80)
    end

    it "returns true for the loopback address" do
      @loopback.ipv6_loopback?.should be_true
    end

    it "returns false for another address" do
      @other.ipv6_loopback?.should be_false
    end
  end

  with_feature :unix_socket do
    describe "for a unix socket" do
      before :each do
        @addrinfo = Addrinfo.unix("/tmp/sock")
      end

      it "returns false" do
        @addrinfo.ipv6_loopback?.should be_false
      end
    end
  end
end
