require_relative '../spec_helper'

describe "Socket.socketpair" do
  it "is an alias of Socket.pair" do
    Socket.method(:socketpair).should == Socket.method(:pair)
  end
end
