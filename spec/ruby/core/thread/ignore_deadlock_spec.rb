require_relative '../../spec_helper'

ruby_version_is "3.0" do
  describe "Thread.ignore_deadlock" do
    it "returns false by default" do
      Thread.ignore_deadlock.should == false
    end
  end

  describe "Thread.ignore_deadlock=" do
    it "changes the value of Thread.ignore_deadlock" do
      ignore_deadlock = Thread.ignore_deadlock
      Thread.ignore_deadlock = true
      begin
        Thread.ignore_deadlock.should == true
      ensure
        Thread.ignore_deadlock = ignore_deadlock
      end
    end
  end
end
