require_relative '../../spec_helper'
require_relative 'shared/dup'

describe "UnboundMethod#dup" do
  ruby_version_is "3.4" do
    it_behaves_like :unboundmethod_dup, :dup

    it "resets frozen status" do
      method = Class.instance_method(:instance_method)
      method.freeze
      method.frozen?.should == true
      method.dup.frozen?.should == false
    end
  end
end
