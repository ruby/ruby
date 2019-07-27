require_relative '../../spec_helper'
require 'resolv'

describe "Resolv#getaddress" do
  it "resolves localhost" do
    hosts = Resolv::Hosts.new(fixture(__FILE__ , "hosts"))
    res = Resolv.new([hosts])

    res.getaddress("localhost").should == "127.0.0.1"
    res.getaddress("localhost4").should == "127.0.0.1"
  end

  it "raises ResolvError if the name can not be looked up" do
    res = Resolv.new([])
    -> {
      res.getaddress("should.raise.error.")
    }.should raise_error(Resolv::ResolvError)
  end
end
