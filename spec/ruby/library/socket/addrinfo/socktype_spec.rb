require_relative '../spec_helper'

describe "Addrinfo#socktype" do
  it 'returns 0 by default' do
    Addrinfo.ip('127.0.0.1').socktype.should == 0
  end

  it 'returns the socket type when given' do
    Addrinfo.tcp('127.0.0.1', 80).socktype.should == Socket::SOCK_STREAM
  end

  with_feature :unix_socket do
    describe "for a unix socket" do
      before :each do
        @addrinfo = Addrinfo.unix("/tmp/sock")
      end

      it "returns Socket::SOCK_STREAM" do
        @addrinfo.socktype.should == Socket::SOCK_STREAM
      end
    end
  end
end
