require_relative '../../spec_helper'

ruby_version_is "2.6" do
  describe "Range#%" do
    it "works as a Range#step" do
      aseq = (1..10) % 2
      aseq.class.should == Enumerator::ArithmeticSequence
      aseq.begin.should == 1
      aseq.end.should == 10
      aseq.step.should == 2
      aseq.to_a.should == [1, 3, 5, 7, 9]
    end

    it "produces an arithmetic sequence with a percent sign in #inspect" do
      ((1..10) % 2).inspect.should == "((1..10).%(2))"
    end
  end
end
