require_relative '../../spec_helper'

describe "Set#map!" do
  before :each do
    @set = Set[1, 2, 3, 4, 5]
  end

  it "yields each Object in self" do
    res = []
    @set.map! { |x| res << x }
    res.sort.should == [1, 2, 3, 4, 5].sort
  end

  it "returns self" do
    @set.map! { |x| x }.should.equal?(@set)
  end

  it "replaces self with the return values of the block" do
    @set.map! { |x| x * 2 }
    @set.should == Set[2, 4, 6, 8, 10]
  end
end
