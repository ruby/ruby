require_relative '../../spec_helper'
require_relative 'shared/dup'

describe "UnboundMethod#clone" do
  it_behaves_like :unboundmethod_dup, :clone

  it "preserves frozen status" do
    method = Class.instance_method(:instance_method)
    method.freeze
    method.frozen?.should == true
    method.clone.frozen?.should == true
  end
end
