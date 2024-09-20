require_relative '../../spec_helper'

describe "Thread.each_caller_location" do
  ruby_version_is "3.2" do
    it "iterates through the current execution stack and matches caller_locations content and type" do
      ScratchPad.record []
      Thread.each_caller_location { |l| ScratchPad << l; }

      ScratchPad.recorded.map(&:to_s).should == caller_locations.map(&:to_s)
      ScratchPad.recorded[0].should be_kind_of(Thread::Backtrace::Location)
    end

    it "returns subset of 'Thread.to_enum(:each_caller_location)' locations" do
      ar = []
      ecl = Thread.each_caller_location { |x| ar << x }

      (ar.map(&:to_s) - Thread.to_enum(:each_caller_location).to_a.map(&:to_s)).should.empty?
    end

    it "stops the backtrace iteration if 'break' occurs" do
      i = 0
      ar = []
      ecl = Thread.each_caller_location do |x|
        ar << x
        i += 1
        break x if i == 2
      end

      ar.map(&:to_s).should == caller_locations(1, 2).map(&:to_s)
      ecl.should be_kind_of(Thread::Backtrace::Location)
    end

    it "returns nil" do
      Thread.each_caller_location {}.should == nil
    end

    it "raises LocalJumpError when called without a block" do
      -> {
        Thread.each_caller_location
      }.should raise_error(LocalJumpError, "no block given")
    end

    it "doesn't accept keyword arguments" do
      -> {
        Thread.each_caller_location(12, foo: 10) {}
      }.should raise_error(ArgumentError);
    end
  end
end
