require_relative '../../spec_helper'
require 'resolv'

describe "Resolv#getnames" do
  it "resolves 127.0.0.1" do
    hosts = Resolv::Hosts.new(fixture(__FILE__ , "hosts"))
    res = Resolv.new([hosts])

    names = res.getnames("127.0.0.1").should == ["localhost", "localhost4"]
  end
end

describe "Resolv.getnames" do
  it "calls DefaultResolver#getnames" do
    Resolv::DefaultResolver.should_receive(:getnames).with("127.0.0.1")
    Resolv.getnames("127.0.0.1")
  end

  ruby_version_is "2.6" do
    context "with a custom resolver" do
      after do
        Resolv.current_resolver = nil
      end

      it "calls #getnames on the custom resolver" do
        resolver = Resolv.new([])
        resolver.should_receive(:getnames).with("127.0.0.1")

        Resolv.current_resolver = resolver
        Resolv.getnames("127.0.0.1")
      end
    end
  end
end
