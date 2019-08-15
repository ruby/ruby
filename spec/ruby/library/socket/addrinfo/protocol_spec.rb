require_relative '../spec_helper'

describe "Addrinfo#protocol" do
  it 'returns 0 by default' do
    Addrinfo.ip('127.0.0.1').protocol.should == 0
  end

  it 'returns a custom protocol when given' do
    Addrinfo.tcp('127.0.0.1', 80).protocol.should == Socket::IPPROTO_TCP
    Addrinfo.tcp('::1', 80).protocol.should == Socket::IPPROTO_TCP
  end

  with_feature :unix_socket do
    describe "for a unix socket" do
      before :each do
        @addrinfo = Addrinfo.unix("/tmp/sock")
      end

      it "returns 0" do
        @addrinfo.protocol.should == 0
      end
    end
  end
end
