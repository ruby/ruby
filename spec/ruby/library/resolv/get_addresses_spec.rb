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

describe "Resolv.getaddresses" do
  it "calls DefaultResolver#getaddresses" do
    Resolv::DefaultResolver.should_receive(:getaddresses).with("localhost")
    Resolv.getaddresses("localhost")
  end

  ruby_version_is "2.6" do
    context "with a custom resolver" do
      after do
        Resolv.current_resolver = nil
      end

      it "calls #getaddresses on the custom resolver" do
        resolver = Resolv.new([])
        resolver.should_receive(:getaddresses).with("localhost")

        Resolv.current_resolver = resolver
        Resolv.getaddresses("localhost")
      end
    end
  end
end
