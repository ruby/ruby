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
      -> { set.replace(Set[1, 2, 3]) }.should.raise(RuntimeError, /iteration/)
    end
    set.should == Set[:a, :b, :c, :d, :e, :f]
  end

  it "accepts any enumerable as other" do
    @set.replace([1, 2, 3]).should == Set[1, 2, 3]
  end

  it "transfers compare_by_identity flag of the argument if it is a Set" do
    set1 = Set[:a].compare_by_identity
    set2 = Set[1, 2]
    set1.replace(set2)
    set1.compare_by_identity?.should == false

    set3 = Set[:a]
    set4 = Set[1, 2].compare_by_identity
    set3.replace(set4)
    set3.compare_by_identity?.should == true
  end

  it "retains compare_by_identity flag if the argument is a non-Set Enumerable" do
    set1 = Set[:a].compare_by_identity
    set1.replace([1, 2])
    set1.compare_by_identity?.should == true
  end
end
