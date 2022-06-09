require_relative '../../spec_helper'
require_relative 'fixtures/caller_locations'

describe 'Kernel#caller_locations' do
  it 'is a private method' do
    Kernel.should have_private_instance_method(:caller_locations)
  end

  it 'returns an Array of caller locations' do
    KernelSpecs::CallerLocationsTest.locations.should_not.empty?
  end

  it 'returns an Array of caller locations using a custom offset' do
    locations = KernelSpecs::CallerLocationsTest.locations(2)

    locations[0].absolute_path.should.end_with?('mspec.rb')
  end

  it 'returns an Array of caller locations using a custom limit' do
    locations = KernelSpecs::CallerLocationsTest.locations(1, 1)

    locations.length.should == 1
  end

  it "can be called with a range" do
    locations1 = caller_locations(0)
    locations2 = caller_locations(2..4)
    locations1[2..4].map(&:to_s).should == locations2.map(&:to_s)
  end

  it "works with endless ranges" do
    locations1 = caller_locations(0)
    locations2 = caller_locations(eval("(2..)"))
    locations2.map(&:to_s).should == locations1[2..-1].map(&:to_s)
  end

  it "works with beginless ranges" do
    locations1 = caller_locations(0)
    locations2 = caller_locations((...5))
    locations2.map(&:to_s)[eval("(2..)")].should == locations1[(...5)].map(&:to_s)[eval("(2..)")]
  end

  it "can be called with a range whose end is negative" do
    locations1 = caller_locations(0)
    locations2 = caller_locations(2..-1)
    locations3 = caller_locations(2..-2)
    locations1[2..-1].map(&:to_s).should == locations2.map(&:to_s)
    locations1[2..-2].map(&:to_s).should == locations3.map(&:to_s)
  end

  it "must return nil if omitting more locations than available" do
    caller_locations(100).should == nil
    caller_locations(100..-1).should == nil
  end

  it "must return [] if omitting exactly the number of locations available" do
    omit = caller_locations(0).length
    caller_locations(omit).should == []
  end

  it 'returns the locations as Thread::Backtrace::Location instances' do
    locations = KernelSpecs::CallerLocationsTest.locations

    locations.each do |location|
      location.kind_of?(Thread::Backtrace::Location).should == true
    end
  end

  it "must return the same locations when called with 1..-1 and when called with no arguments" do
    caller_locations.map(&:to_s).should == caller_locations(1..-1).map(&:to_s)
  end

  guard -> { Kernel.instance_method(:tap).source_location } do
    it "includes core library methods defined in Ruby" do
      file, line = Kernel.instance_method(:tap).source_location
      file.should.start_with?('<internal:')

      loc = nil
      tap { loc = caller_locations(1, 1)[0] }
      loc.label.should == "tap"
      loc.path.should.start_with? "<internal:"
    end
  end
end
