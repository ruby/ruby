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
    backtrace.first.should =~ /[`'](?:Kernel#)?sleep'/

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

  it "can be called with a number of locations to omit" do
    locations1 = Thread.current.backtrace
    locations2 = Thread.current.backtrace(2)
    locations1[2..-1].length.should == locations2.length
    locations1[2..-1].map(&:to_s).should == locations2.map(&:to_s)
  end

  it "can be called with a maximum number of locations to return as second parameter" do
    locations1 = Thread.current.backtrace
    locations2 = Thread.current.backtrace(2, 3)
    locations1[2..4].map(&:to_s).should == locations2.map(&:to_s)
  end

  it "can be called with a range" do
    locations1 = Thread.current.backtrace
    locations2 = Thread.current.backtrace(2..4)
    locations1[2..4].map(&:to_s).should == locations2.map(&:to_s)
  end

  it "can be called with a range whose end is negative" do
    Thread.current.backtrace(2..-1).should == Thread.current.backtrace[2..-1]
    Thread.current.backtrace(2..-2).should == Thread.current.backtrace[2..-2]
  end

  it "returns nil if omitting more locations than available" do
    Thread.current.backtrace(100).should == nil
    Thread.current.backtrace(100..-1).should == nil
  end

  it "returns [] if omitting exactly the number of locations available" do
    omit = Thread.current.backtrace.length
    Thread.current.backtrace(omit).should == []
  end
end
