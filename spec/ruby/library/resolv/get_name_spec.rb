require_relative '../../spec_helper'
require 'resolv'

describe "Resolv#getname" do
  it "resolves 127.0.0.1" do
    hosts = Resolv::Hosts.new(fixture(__FILE__ , "hosts"))
    res = Resolv.new([hosts])

    res.getname("127.0.0.1").should == "localhost"
  end

  it "raises ResolvError when there is no result" do
    res = Resolv.new([])
    -> {
      res.getname("should.raise.error")
    }.should raise_error(Resolv::ResolvError)
  end
end

describe "Resolv.getname" do
  it "calls DefaultResolver#getname" do
    Resolv::DefaultResolver.should_receive(:getname).with("127.0.0.1")
    Resolv.getname("127.0.0.1")
  end

  ruby_version_is "2.6" do
    context "with a custom resolver" do
      after do
        Resolv.current_resolver = nil
      end

      it "calls #getname on the custom resolver" do
        resolver = Resolv.new([])
        resolver.should_receive(:getname).with("127.0.0.1")

        Resolv.current_resolver = resolver
        Resolv.getname("127.0.0.1")
      end
    end
  end
end
