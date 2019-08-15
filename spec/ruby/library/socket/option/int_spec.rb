require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket::Option.int" do
  it "creates a new Socket::Option" do
    so = Socket::Option.int(:INET, :SOCKET, :KEEPALIVE, 5)
    so.should be_an_instance_of(Socket::Option)
    so.family.should == Socket::Constants::AF_INET
    so.level.should == Socket::Constants::SOL_SOCKET
    so.optname.should == Socket::Constants::SO_KEEPALIVE
    so.data.should == [5].pack('i')
  end

  it 'returns a Socket::Option' do
    opt = Socket::Option.int(:INET, :IP, :TTL, 4)

    opt.should be_an_instance_of(Socket::Option)

    opt.family.should  == Socket::AF_INET
    opt.level.should   == Socket::IPPROTO_IP
    opt.optname.should == Socket::IP_TTL
    opt.data.should    == [4].pack('i')
  end
end

describe "Socket::Option#int" do
  it "returns int value" do
    so = Socket::Option.int(:INET, :SOCKET, :KEEPALIVE, 17)
    so.int.should == 17

    so = Socket::Option.int(:INET, :SOCKET, :KEEPALIVE, 32765)
    so.int.should == 32765

    Socket::Option.int(:INET, :IP, :TTL, 4).int.should == 4
  end

  platform_is_not :windows do
    it 'raises TypeError when called on a non integer option' do
      opt = Socket::Option.linger(1, 4)
      -> { opt.int }.should raise_error(TypeError)
    end
  end
end
