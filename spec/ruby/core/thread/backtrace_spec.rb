require_relative '../../spec_helper'

describe "Thread#backtrace" do
  it "returns the current backtrace of a thread" do
    t = Thread.new do
      begin
        sleep
      rescue
      end
    end

    Thread.pass while t.status && t.status != 'sleep'

    backtrace = t.backtrace
    backtrace.should be_kind_of(Array)
    backtrace.first.should =~ /`sleep'/

    t.raise 'finish the thread'
    t.join
  end

  it "returns nil for dead thread" do
    t = Thread.new {}
    t.join
    t.backtrace.should == nil
  end

  it "returns an array (which may be empty) immediately after the thread is created" do
    t = Thread.new { sleep }
    backtrace = t.backtrace
    t.kill
    t.join
    backtrace.should be_kind_of(Array)
  end
end
