require_relative '../spec_helper'

describe "Socket.pack_sockaddr_un" do
  it "is an alias of Socket.sockaddr_un" do
    Socket.method(:pack_sockaddr_un).should == Socket.method(:sockaddr_un)
  end
end
