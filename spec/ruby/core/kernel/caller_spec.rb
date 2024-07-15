require_relative '../../spec_helper'
require_relative 'fixtures/caller'

describe 'Kernel#caller' do
  it 'is a private method' do
    Kernel.should have_private_instance_method(:caller)
  end

  it 'returns an Array of caller locations' do
    KernelSpecs::CallerTest.locations.should_not.empty?
  end

  it 'returns an Array of caller locations using a custom offset' do
    locations = KernelSpecs::CallerTest.locations(2)

    locations[0].should =~ %r{runner/mspec.rb}
  end

  it 'returns an Array of caller locations using a custom limit' do
    locations = KernelSpecs::CallerTest.locations(1, 1)

    locations.length.should == 1
  end

  it 'returns an Array of caller locations using a range' do
    locations = KernelSpecs::CallerTest.locations(1..1)

    locations.length.should == 1
  end

  it 'returns the locations as String instances' do
    locations = KernelSpecs::CallerTest.locations
    line      = __LINE__ - 1

    locations[0].should include("#{__FILE__}:#{line}:in")
  end

  it "returns an Array with the block given to #at_exit at the base of the stack" do
    path = fixture(__FILE__, "caller_at_exit.rb")
    lines = ruby_exe(path).lines
    lines.size.should == 2
    lines[0].should =~ /\A#{path}:6:in [`'](?:Object#)?foo'\n\z/
    lines[1].should =~ /\A#{path}:2:in [`']block in <main>'\n\z/
  end

  it "can be called with a range" do
    locations1 = caller(0)
    locations2 = caller(2..4)
    locations1[2..4].should == locations2
  end

  it "works with endless ranges" do
    locations1 = KernelSpecs::CallerTest.locations(0)
    locations2 = KernelSpecs::CallerTest.locations(eval("(2..)"))
    locations2.should == locations1[2..-1]
  end

  it "works with beginless ranges" do
    locations1 = KernelSpecs::CallerTest.locations(0)
    locations2 = KernelSpecs::CallerTest.locations((..5))
    locations2[eval("(2..)")].should == locations1[(..5)][eval("(2..)")]
  end

  it "can be called with a range whose end is negative" do
    locations1 = caller(0)
    locations2 = caller(2..-1)
    locations3 = caller(2..-2)
    locations1[2..-1].should == locations2
    locations1[2..-2].should == locations3
  end

  it "must return nil if omitting more locations than available" do
    caller(100).should == nil
    caller(100..-1).should == nil
  end

  it "must return [] if omitting exactly the number of locations available" do
    omit = caller(0).length
    caller(omit).should == []
  end

  it "must return the same locations when called with 1..-1 and when called with no arguments" do
    caller.should == caller(1..-1)
  end

  guard -> { Kernel.instance_method(:tap).source_location } do
    it "includes core library methods defined in Ruby" do
      file, line = Kernel.instance_method(:tap).source_location
      file.should.start_with?('<internal:')

      loc = nil
      tap { loc = caller(1, 1)[0] }
      loc.should =~ /\A<internal:.*in [`'](?:Kernel#)?tap'\z/
    end
  end
end
