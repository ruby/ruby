require_relative '../../spec_helper'

describe "Queue#length" do
  it "is an alias of Queue#size" do
    Queue.instance_method(:length).should == Queue.instance_method(:size)
  end
end
