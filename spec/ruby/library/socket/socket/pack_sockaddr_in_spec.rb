require_relative '../spec_helper'

describe "Socket.pack_sockaddr_in" do
  it "is an alias of Socket.sockaddr_in" do
    Socket.method(:pack_sockaddr_in).should == Socket.method(:sockaddr_in)
  end
end
