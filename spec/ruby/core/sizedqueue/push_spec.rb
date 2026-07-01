require_relative '../../spec_helper'

describe "SizedQueue#push" do
  it "is an alias of SizedQueue#<<" do
    SizedQueue.instance_method(:push).should == SizedQueue.instance_method(:<<)
  end
end
