require_relative '../../../spec_helper'

ruby_version_is "2.6" do
  describe "Enumerator::ArithmeticSequence#inspect" do
    context 'when Numeric#step is used' do
      it "returns '(begin.step(end{, step}))'" do
        1.step(10).inspect.should == "(1.step(10))"
        1.step(10, 3).inspect.should == "(1.step(10, 3))"
      end
    end

    context 'when Range#step is used' do
      it "returns '((range).step{(step)})'" do
        (1..10).step.inspect.should == "((1..10).step)"
        (1..10).step(3).inspect.should == "((1..10).step(3))"

        (1...10).step.inspect.should == "((1...10).step)"
        (1...10).step(3).inspect.should == "((1...10).step(3))"
      end
    end
  end
end
