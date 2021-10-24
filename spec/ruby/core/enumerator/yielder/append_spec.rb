require_relative '../../../spec_helper'

describe "Enumerator::Yielder#<<" do
  # TODO: There's some common behavior between yield and <<; move to a shared spec
  it "yields the value to the block" do
    ary = []
    y = Enumerator::Yielder.new {|x| ary << x}
    y << 1

    ary.should == [1]
  end

  it "doesn't double-wrap Arrays" do
    yields = []
    y = Enumerator::Yielder.new {|args| yields << args }
    y << [1]
    yields.should == [[1]]
  end

  it "returns self" do
    y = Enumerator::Yielder.new {|x| x + 1}
    (y << 1).should equal(y)
  end

  context "when multiple arguments passed" do
    it "raises an ArgumentError" do
      ary = []
      y = Enumerator::Yielder.new { |*x| ary << x }

      -> {
        y.<<(1, 2)
      }.should raise_error(ArgumentError, /wrong number of arguments/)
    end
  end
end
