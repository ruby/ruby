require_relative '../spec_helper'

describe "UNIXSocket.socketpair" do
  it "is an alias of UNIXSocket.pair" do
    UNIXSocket.method(:socketpair).should == UNIXSocket.method(:pair)
  end
end
