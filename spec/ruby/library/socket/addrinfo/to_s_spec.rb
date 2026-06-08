require_relative '../spec_helper'

describe "Addrinfo#to_s" do
  it "is an alias of Addrinfo#to_sockaddr" do
    Addrinfo.instance_method(:to_s).should == Addrinfo.instance_method(:to_sockaddr)
  end
end
