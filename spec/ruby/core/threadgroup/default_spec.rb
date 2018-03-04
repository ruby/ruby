require_relative '../../spec_helper'

describe "ThreadGroup::Default" do
  it "is a ThreadGroup instance" do
    ThreadGroup::Default.should be_kind_of(ThreadGroup)
  end

  it "is the ThreadGroup of the main thread" do
    ThreadGroup::Default.should == Thread.main.group
  end
end
