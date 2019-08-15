require_relative '../../spec_helper'
require 'resolv'

describe "Resolv#getnames" do
  it "resolves 127.0.0.1" do
    hosts = Resolv::Hosts.new(fixture(__FILE__ , "hosts"))
    res = Resolv.new([hosts])

    names = res.getnames("127.0.0.1").should == ["localhost", "localhost4"]
  end
end
