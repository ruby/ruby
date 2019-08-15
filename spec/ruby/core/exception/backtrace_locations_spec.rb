require_relative '../../spec_helper'
require_relative 'fixtures/common'

describe "Exception#backtrace_locations" do
  before :each do
    @backtrace = ExceptionSpecs::Backtrace.backtrace_locations
  end

  it "returns nil if no backtrace was set" do
    Exception.new.backtrace_locations.should be_nil
  end

  it "returns an Array" do
    @backtrace.should be_an_instance_of(Array)
  end

  it "sets each element to a Thread::Backtrace::Location" do
    @backtrace.each {|l| l.should be_an_instance_of(Thread::Backtrace::Location)}
  end

  it "produces a backtrace for an exception captured using $!" do
    exception = begin
      raise
    rescue RuntimeError
      $!
    end

    exception.backtrace_locations.first.path.should =~ /backtrace_locations_spec/
  end

  it "returns an Array that can be updated" do
    begin
      raise
    rescue RuntimeError => e
      e.backtrace_locations.unshift "backtrace first"
      e.backtrace_locations[0].should == "backtrace first"
    end
  end
end
