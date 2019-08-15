require_relative '../spec_helper'

describe "Addrinfo#ipv6?" do
  describe "for an ipv4 socket" do
    before :each do
      @addrinfo = Addrinfo.tcp("10.0.0.1", 80)
    end

    it "returns true" do
      @addrinfo.ipv6?.should be_false
    end
  end

  describe "for an ipv6 socket" do
    before :each do
      @addrinfo = Addrinfo.tcp("::1", 80)
    end

    it "returns false" do
      @addrinfo.ipv6?.should be_true
    end
  end

  with_feature :unix_socket do
    describe "for a unix socket" do
      before :each do
        @addrinfo = Addrinfo.unix("/tmp/sock")
      end

      it "returns false" do
        @addrinfo.ipv6?.should be_false
      end
    end
  end
end
