require_relative '../../../spec_helper'

describe "Enumerator::Yielder#to_proc" do
  it "returns a Proc object that takes an argument and yields it to the block" do
    ScratchPad.record []
    y = Enumerator::Yielder.new { |*args| ScratchPad << args; "foobar" }

    callable = y.to_proc
    callable.class.should == Proc

    result = callable.call(1, 2)
    ScratchPad.recorded.should == [[1, 2]]

    result.should == "foobar"
  end
end
