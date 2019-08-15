require_relative '../../spec_helper'
require_relative 'shared/cover_and_include'
require_relative 'shared/cover'

describe "Range#===" do
  ruby_version_is ""..."2.6" do
    it "returns the result of calling #include? on self" do
      range = 0...10
      range.should_receive(:include?).with(2).and_return(:true)
      (range === 2).should == :true
    end

    it "requires #succ method to be implemented" do
      range = RangeSpecs::WithoutSucc.new(0)..RangeSpecs::WithoutSucc.new(10)

      -> do
        range === RangeSpecs::WithoutSucc.new(2)
      end.should raise_error(TypeError, /can't iterate from/)
    end
  end

  ruby_version_is "2.6" do
    it "returns the result of calling #cover? on self" do
      range = RangeSpecs::WithoutSucc.new(0)..RangeSpecs::WithoutSucc.new(10)
      (range === RangeSpecs::WithoutSucc.new(2)).should == true
    end
  end
end
