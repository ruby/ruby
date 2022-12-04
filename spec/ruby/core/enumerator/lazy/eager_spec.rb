require_relative '../../../spec_helper'

describe "Enumerator::Lazy#eager" do
  it "returns a non-lazy Enumerator converted from the lazy enumerator" do
    enum = [1, 2, 3].lazy

    enum.class.should == Enumerator::Lazy
    enum.eager.class.should == Enumerator
  end

  it "does not enumerate an enumerator" do
    ScratchPad.record []

    sequence = [1, 2, 3]
    enum_lazy = Enumerator::Lazy.new(sequence) do |yielder, value|
      yielder << value
      ScratchPad << value
    end

    ScratchPad.recorded.should == []
    enum = enum_lazy.eager
    ScratchPad.recorded.should == []

    enum.map { |i| i }.should == [1, 2, 3]
    ScratchPad.recorded.should == [1, 2, 3]
  end
end
