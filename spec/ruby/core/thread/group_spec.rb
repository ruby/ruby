require_relative '../../spec_helper'

describe "Thread#group" do
  it "returns the default thread group for the main thread" do
    Thread.main.group.should == ThreadGroup::Default
  end

  it "returns the thread group explicitly set for this thread" do
    thread = Thread.new { nil }
    thread_group = ThreadGroup.new
    thread_group.add(thread)
    thread.group.should == thread_group
  ensure
    thread.join if thread
  end
end
