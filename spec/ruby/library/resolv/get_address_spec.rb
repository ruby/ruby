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

describe "Resolv.getaddress" do
  it "calls DefaultResolver#getaddress" do
    Resolv::DefaultResolver.should_receive(:getaddress).with("localhost")
    Resolv.getaddress("localhost")
  end

  ruby_version_is "2.6" do
    context "with a custom resolver" do
      after do
        Resolv.current_resolver = nil
      end

      it "calls #getaddress on the custom resolver" do
        resolver = Resolv.new([])
        resolver.should_receive(:getaddress).with("localhost")

        Resolv.current_resolver = resolver
        Resolv.getaddress("localhost")
      end
    end
  end
end
