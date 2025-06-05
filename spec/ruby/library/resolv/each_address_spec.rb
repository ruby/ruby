require_relative '../../spec_helper'
require 'resolv'

describe "Resolv.each_address" do
  it "calls DefaultResolver#each_address" do
    Resolv::DefaultResolver.should_receive(:each_address).with("localhost")
    Resolv.each_address("localhost")
  end

  ruby_version_is "2.6" do
    context "with a custom resolver" do
      after do
        Resolv.current_resolver = nil
      end

      it "calls #each_address on the custom resolver" do
        resolver = Resolv.new([])
        resolver.should_receive(:each_address).with("localhost")

        Resolv.current_resolver = resolver
        Resolv.each_address("localhost")
      end
    end
  end
end
