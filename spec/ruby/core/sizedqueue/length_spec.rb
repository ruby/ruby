require_relative '../../spec_helper'

describe "SizedQueue#length" do
  it "is an alias of SizedQueue#size" do
    SizedQueue.instance_method(:length).should == SizedQueue.instance_method(:size)
  end
end
