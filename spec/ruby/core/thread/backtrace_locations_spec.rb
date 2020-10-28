require_relative '../../spec_helper'

describe "Thread#backtrace_locations" do
  it "returns an Array" do
    locations = Thread.current.backtrace_locations
    locations.should be_an_instance_of(Array)
    locations.should_not be_empty
  end

  it "sets each element to a Thread::Backtrace::Location" do
    locations = Thread.current.backtrace_locations
    locations.each { |loc| loc.should be_an_instance_of(Thread::Backtrace::Location) }
  end

  it "can be called on any Thread" do
    locations = Thread.new { Thread.current.backtrace_locations }.value
    locations.should be_an_instance_of(Array)
    locations.should_not be_empty
    locations.each { |loc| loc.should be_an_instance_of(Thread::Backtrace::Location) }
  end

  it "can be called with a number of locations to omit" do
    locations1 = Thread.current.backtrace_locations
    locations2 = Thread.current.backtrace_locations(2)
    locations2.length.should == locations1[2..-1].length
    locations2.map(&:to_s).should == locations1[2..-1].map(&:to_s)
  end

  it "can be called with a maximum number of locations to return as second parameter" do
    locations1 = Thread.current.backtrace_locations
    locations2 = Thread.current.backtrace_locations(2, 3)
    locations2.map(&:to_s).should == locations1[2..4].map(&:to_s)
  end

  it "can be called with a range" do
    locations1 = Thread.current.backtrace_locations
    locations2 = Thread.current.backtrace_locations(2..4)
    locations2.map(&:to_s).should == locations1[2..4].map(&:to_s)
  end

  it "can be called with a range whose end is negative" do
    Thread.current.backtrace_locations(2..-1).map(&:to_s).should == Thread.current.backtrace_locations[2..-1].map(&:to_s)
    Thread.current.backtrace_locations(2..-2).map(&:to_s).should == Thread.current.backtrace_locations[2..-2].map(&:to_s)
  end

  ruby_version_is "2.6" do
    it "can be called with an endless range" do
      locations1 = Thread.current.backtrace_locations(0)
      locations2 = Thread.current.backtrace_locations(eval("(2..)"))
      locations2.map(&:to_s).should == locations1[2..-1].map(&:to_s)
    end
  end

  it "returns nil if omitting more locations than available" do
    Thread.current.backtrace_locations(100).should == nil
    Thread.current.backtrace_locations(100..-1).should == nil
  end

  it "returns [] if omitting exactly the number of locations available" do
    omit = Thread.current.backtrace_locations.length
    Thread.current.backtrace_locations(omit).should == []
  end

  it "without argument is the same as showing all locations with 0..-1" do
    Thread.current.backtrace_locations.map(&:to_s).should == Thread.current.backtrace_locations(0..-1).map(&:to_s)
  end

  it "the first location reports the call to #backtrace_locations" do
    Thread.current.backtrace_locations(0..0)[0].to_s.should == "#{__FILE__ }:#{__LINE__ }:in `backtrace_locations'"
  end

  it "[1..-1] is the same as #caller_locations(0..-1) for Thread.current" do
    Thread.current.backtrace_locations(1..-1).map(&:to_s).should == caller_locations(0..-1).map(&:to_s)
  end
end
