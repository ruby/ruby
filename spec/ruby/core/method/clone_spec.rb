require_relative '../../spec_helper'
require_relative 'shared/dup'

describe "Method#clone" do
  it_behaves_like :method_dup, :clone

  it "preserves frozen status" do
    method = Object.new.method(:method)
    method.freeze
    method.frozen?.should == true
    method.clone.frozen?.should == true
  end
end
