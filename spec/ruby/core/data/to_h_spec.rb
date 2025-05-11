require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Data#to_h" do
  it "transforms the data object into a hash" do
    data = DataSpecs::Measure.new(amount: 42, unit: 'km')
    data.to_h.should == { amount: 42, unit: 'km' }
  end

  context "with block" do
    it "transforms [key, value] pairs returned by the block into a hash" do
      data = DataSpecs::Measure.new(amount: 42, unit: 'km')
      data.to_h { |key, value| [value, key] }.should == { 42 => :amount, 'km' => :unit }
    end

    it "passes to a block each pair's key and value as separate arguments" do
      ScratchPad.record []
      data = DataSpecs::Measure.new(amount: 42, unit: 'km')
      data.to_h { |k, v| ScratchPad << [k, v]; [k, v] }
      ScratchPad.recorded.sort.should == [[:amount, 42], [:unit, 'km']]

      ScratchPad.record []
      data.to_h { |*args| ScratchPad << args; [args[0], args[1]] }
      ScratchPad.recorded.sort.should == [[:amount, 42], [:unit, 'km']]
    end

    it "raises ArgumentError if block returns longer or shorter array" do
      data = DataSpecs::Measure.new(amount: 42, unit: 'km')
      -> do
        data.to_h { |k, v| [k.to_s, v*v, 1] }
      end.should raise_error(ArgumentError, /element has wrong array length/)

      -> do
        data.to_h { |k, v| [k] }
      end.should raise_error(ArgumentError, /element has wrong array length/)
    end

    it "raises TypeError if block returns something other than Array" do
      data = DataSpecs::Measure.new(amount: 42, unit: 'km')
      -> do
        data.to_h { |k, v| "not-array" }
      end.should raise_error(TypeError, /wrong element type String/)
    end

    it "coerces returned pair to Array with #to_ary" do
      x = mock('x')
      x.stub!(:to_ary).and_return([:b, 'b'])
      data = DataSpecs::Measure.new(amount: 42, unit: 'km')

      data.to_h { |k| x }.should == { :b => 'b' }
    end

    it "does not coerce returned pair to Array with #to_a" do
      x = mock('x')
      x.stub!(:to_a).and_return([:b, 'b'])
      data = DataSpecs::Measure.new(amount: 42, unit: 'km')

      -> do
        data.to_h { |k| x }
      end.should raise_error(TypeError, /wrong element type MockObject/)
    end
  end
end
