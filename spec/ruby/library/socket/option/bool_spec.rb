require_relative '../spec_helper'
require_relative '../fixtures/classes'

describe "Socket::Option.bool" do
  it "creates a new Socket::Option" do
    so = Socket::Option.bool(:INET, :SOCKET, :KEEPALIVE, true)
    so.should be_an_instance_of(Socket::Option)
    so.family.should == Socket::AF_INET
    so.level.should == Socket::SOL_SOCKET
    so.optname.should == Socket::SO_KEEPALIVE
    so.data.should == [1].pack('i')
  end
end

describe "Socket::Option#bool" do
  it "returns boolean value" do
    Socket::Option.bool(:INET, :SOCKET, :KEEPALIVE, true).bool.should == true
    Socket::Option.bool(:INET, :SOCKET, :KEEPALIVE, false).bool.should == false
  end

  platform_is_not :windows do
    it 'raises TypeError when called on a non boolean option' do
      opt = Socket::Option.linger(1, 4)
      lambda { opt.bool }.should raise_error(TypeError)
    end
  end
end
