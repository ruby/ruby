require_relative '../../spec_helper'
require_relative 'shared/iterable_and_tolerating_size_increasing'

describe "Array#find_index" do
  it "returns the index of the first element == to object" do
    x = mock('3')
    def x.==(obj) 3 == obj; end

    [2, x, 3, 1, 3, 1].find_index(3).should == 1
    [2, 3.0, 3, x, 1, 3, 1].find_index(x).should == 1
  end

  it "returns 0 if first element == to object" do
    [2, 1, 3, 2, 5].find_index(2).should == 0
  end

  it "returns size-1 if only last element == to object" do
    [2, 1, 3, 1, 5].find_index(5).should == 4
  end

  it "returns nil if no element == to object" do
    [2, 1, 1, 1, 1].find_index(3).should == nil
  end

  it "accepts a block instead of an argument" do
    [4, 2, 1, 5, 1, 3].find_index {|x| x < 2}.should == 2
  end

  it "ignores the block if there is an argument" do
    -> {
      [4, 2, 1, 5, 1, 3].find_index(5) {|x| x < 2}.should == 3
    }.should complain(/given block not used/)
  end

  describe "given no argument and no block" do
    it "produces an Enumerator" do
      [].find_index.should.instance_of?(Enumerator)
    end
  end

  it_behaves_like :array_iterable_and_tolerating_size_increasing, :find_index
end
