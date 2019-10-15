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
