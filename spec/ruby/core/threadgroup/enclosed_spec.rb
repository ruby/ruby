require_relative '../../spec_helper'

describe "ThreadGroup#enclosed?" do
  it "returns false when a ThreadGroup has not been enclosed (default state)" do
    thread_group = ThreadGroup.new
    thread_group.enclosed?.should be_false
  end

  it "returns true when a ThreadGroup is enclosed" do
    thread_group = ThreadGroup.new
    thread_group.enclose
    thread_group.enclosed?.should be_true
  end
end
