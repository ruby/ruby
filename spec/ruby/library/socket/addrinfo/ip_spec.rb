require_relative '../../../spec_helper'
require 'socket'

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

  platform_is_not :windows do
    describe "for a unix socket" do
      before :each do
        @addrinfo = Addrinfo.unix("/tmp/sock")
      end

      it "returns Socket::AF_INET6" do
        @addrinfo.ip?.should be_false
      end
    end
  end
end
