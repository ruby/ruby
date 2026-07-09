require_relative '../../spec_helper'

describe "Thread#terminate" do
  it "is an alias of Thread#kill" do
    Thread.instance_method(:terminate).should == Thread.instance_method(:kill)
  end
end
