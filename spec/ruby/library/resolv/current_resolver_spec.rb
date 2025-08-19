require_relative '../../spec_helper'
require 'resolv'

ruby_version_is "2.6" do
  describe "Resolv.current_resolver" do
    it "returns the resolver for the current thread, or the default resolver" do
      Resolv.current_resolver.should == Resolv::DefaultResolver

      Thread.new do
        Resolv.current_resolver.should == Resolv::DefaultResolver
        new_resolver = Resolv.new
        Resolv.current_resolver = new_resolver
        Resolv.current_resolver.should == new_resolver
      end.join

      Resolv.current_resolver.should == Resolv::DefaultResolver
    end
  end
end
