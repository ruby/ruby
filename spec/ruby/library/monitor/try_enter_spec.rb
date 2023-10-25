require_relative '../../spec_helper'
require 'monitor'

describe "Monitor#try_enter" do
  it "will acquire a monitor not held by another thread" do
    monitor = Monitor.new
    10.times do

      thread = Thread.new do
        val = monitor.try_enter
        monitor.exit if val
        val
      end

      thread.join
      thread.value.should == true
    end
  end

  it "will not acquire a monitor already held by another thread" do
    monitor = Monitor.new
    10.times do
      monitor.enter
      begin
        thread = Thread.new do
          val = monitor.try_enter
          monitor.exit if val
          val
        end

        thread.join
        thread.value.should == false
      ensure
        monitor.exit
      end
      monitor.mon_locked?.should == false
    end
  end
end
