require_relative '../../spec_helper'

describe "Thread.fork" do
  it "is an alias of Thread.start" do
    Thread.method(:fork).should == Thread.method(:start)
  end
end
