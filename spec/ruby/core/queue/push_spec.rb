require_relative '../../spec_helper'

describe "Queue#push" do
  it "is an alias of Queue#<<" do
    Queue.instance_method(:push).should == Queue.instance_method(:<<)
  end
end
