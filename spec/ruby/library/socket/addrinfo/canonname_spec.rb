require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Addrinfo#canonname" do

  before :each do
    @addrinfos = Addrinfo.getaddrinfo("localhost", 80, :INET, :STREAM, nil, Socket::AI_CANONNAME)
  end

  it "returns the canonical name for a host" do
    canonname = @addrinfos.map { |a| a.canonname }.find { |name| name and name.include?("localhost") }
    if canonname
      canonname.should include("localhost")
    else
      canonname.should == nil
    end
  end

  describe 'when the canonical name is not available' do
    it 'returns nil' do
      addr = Addrinfo.new(Socket.sockaddr_in(0, '127.0.0.1'))

      addr.canonname.should be_nil
    end
  end

end
