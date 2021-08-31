require_relative '../../spec_helper'
require 'monitor'

describe "Monitor#synchronize" do
  it "unlocks after return, even if it was interrupted by Thread#raise" do
    exc_class = Class.new(RuntimeError)

    monitor = Monitor.new
    10.times do
      wait_q = Queue.new
      continue_q = Queue.new

      thread = Thread.new do
        begin
          monitor.synchronize do
            wait_q << true
            # Do not wait here, we are trying to interrupt the ensure part of #synchronize
          end
          continue_q.pop
        rescue exc_class
          monitor.should_not.mon_locked?
          :ok
        end
      end

      wait_q.pop
      thread.raise exc_class, "interrupt"
      continue_q << true
      thread.value.should == :ok
    end
  end

  it "raises a LocalJumpError if not passed a block" do
    -> { Monitor.new.synchronize }.should raise_error(LocalJumpError)
  end

  it "raises a thread error if the monitor is not owned on exiting the block" do
    monitor = Monitor.new
    -> { monitor.synchronize { monitor.exit } }.should raise_error(ThreadError)
  end
end
