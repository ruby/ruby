require_relative '../../spec_helper'

describe "Thread#inspect" do
  it "is an alias of Thread#to_s" do
    Thread.instance_method(:inspect).should == Thread.instance_method(:to_s)
  end
end
