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
end
