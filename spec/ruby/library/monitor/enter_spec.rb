require_relative '../../spec_helper'
require 'monitor'

describe "Monitor#enter" do
  it "acquires the monitor" do
    monitor = Monitor.new
    10.times do
      wait_q = Queue.new
      continue_q = Queue.new

      thread = Thread.new do
        begin
          monitor.enter
          wait_q << true
          continue_q.pop
        ensure
          monitor.exit
        end
      end

      wait_q.pop
      monitor.mon_locked?.should == true
      continue_q << true
      thread.join
      monitor.mon_locked?.should == false
    end
  end
end
