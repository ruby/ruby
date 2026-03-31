require_relative '../../spec_helper'

describe "Set#replace" do
  before :each do
    @set = Set[:a, :b, :c]
  end

  it "replaces the contents with other and returns self" do
    @set.replace(Set[1, 2, 3]).should == @set
    @set.should == Set[1, 2, 3]
  end

  it "raises RuntimeError when called during iteration" do
    set = Set[:a, :b, :c, :d, :e, :f]
    set.each do |_m|
      -> { set.replace(Set[1, 2, 3]) }.should raise_error(RuntimeError, /iteration/)
    end
    set.should == Set[:a, :b, :c, :d, :e, :f]
  end

  it "accepts any enumerable as other" do
    @set.replace([1, 2, 3]).should == Set[1, 2, 3]
  end
end
