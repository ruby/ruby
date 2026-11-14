require_relative '../../spec_helper'
require 'resolv'

describe "Resolv.each_name" do
  it "calls DefaultResolver#each_name" do
    Resolv::DefaultResolver.should_receive(:each_name).with("127.0.0.1")
    Resolv.each_name("127.0.0.1")
  end

  ruby_version_is "2.6" do
    context "with a custom resolver" do
      after do
        Resolv.current_resolver = nil
      end

      it "calls #each_name on the custom resolver" do
        resolver = Resolv.new([])
        resolver.should_receive(:each_name).with("127.0.0.1")

        Resolv.current_resolver = resolver
        Resolv.each_name("127.0.0.1")
      end
    end
  end
end
