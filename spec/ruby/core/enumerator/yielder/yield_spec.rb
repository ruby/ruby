require_relative '../../../spec_helper'

describe "Enumerator::Yielder#yield" do
  it "yields the value to the block" do
    ary = []
    y = Enumerator::Yielder.new {|x| ary << x}
    y.yield 1

    ary.should == [1]
  end

  it "yields with passed arguments" do
    yields = []
    y = Enumerator::Yielder.new {|*args| yields << args }
    y.yield 1, 2
    yields.should == [[1, 2]]
  end

  it "returns the result of the block for the given value" do
    y = Enumerator::Yielder.new {|x| x + 1}
    y.yield(1).should == 2
  end

  context "when multiple arguments passed" do
    it "yields the arguments list to the block" do
      ary = []
      y = Enumerator::Yielder.new { |*x| ary << x }
      y.yield(1, 2)

      ary.should == [[1, 2]]
    end
  end
end
