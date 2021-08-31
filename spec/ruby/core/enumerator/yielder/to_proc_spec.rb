require_relative '../../../spec_helper'

ruby_version_is "2.7" do
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
end
