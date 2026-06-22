require_relative '../../spec_helper'

describe "ThreadGroup::Default" do
  it "is a ThreadGroup instance" do
    ThreadGroup::Default.should.is_a?(ThreadGroup)
  end

  it "is the ThreadGroup of the main thread" do
    ThreadGroup::Default.should == Thread.main.group
  end
end
