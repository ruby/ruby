require_relative '../../spec_helper'
require 'resolv'

describe "Resolv#getaddresses" do
  it "resolves localhost" do
    hosts = Resolv::Hosts.new(fixture(__FILE__ , "hosts"))
    res = Resolv.new([hosts])

    res.getaddresses("localhost").should == ["127.0.0.1"]
    res.getaddresses("localhost4").should == ["127.0.0.1"]
  end
end
