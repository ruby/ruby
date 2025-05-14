require_relative '../../spec_helper'

describe "Set#divide" do
  it "divides self into a set of subsets based on the blocks return values" do
    set = Set["one", "two", "three", "four", "five"].divide { |x| x.length }
    set.map { |x| x.to_a.sort }.sort.should == [["five", "four"], ["one", "two"], ["three"]]
  end

  it "yields each Object to the block" do
    ret = []
    Set["one", "two", "three", "four", "five"].divide { |x| ret << x }
    ret.sort.should == ["five", "four", "one", "three", "two"]
  end

  it "returns an enumerator when not passed a block" do
    ret = Set[1, 2, 3, 4].divide
    ret.should be_kind_of(Enumerator)
    ret.each(&:even?).should == Set[Set[1, 3], Set[2, 4]]
  end
end

describe "Set#divide when passed a block with an arity of 2" do
  it "divides self into a set of subsets based on the blocks return values" do
    set = Set[1, 3, 4, 6, 9, 10, 11].divide { |x, y| (x - y).abs == 1 }
    set.map{ |x| x.to_a.sort }.sort.should == [[1], [3, 4], [6], [9, 10, 11]]
  end

  ruby_version_is "3.5" do
    it "yields each two Object to the block" do
      ret = []
      Set[1, 2].divide { |x, y| ret << [x, y] }
      ret.sort.should == [[1, 2], [2, 1]]
    end
  end

  ruby_version_is ""..."3.5" do
    it "yields each two Object to the block" do
      ret = []
      Set[1, 2].divide { |x, y| ret << [x, y] }
      ret.sort.should == [[1, 1], [1, 2], [2, 1], [2, 2]]
    end
  end

  it "returns an enumerator when not passed a block" do
    ret = Set[1, 2, 3, 4].divide
    ret.should be_kind_of(Enumerator)
    ret.each { |a, b| (a + b).even? }.should == Set[Set[1, 3], Set[2, 4]]
  end
end

describe "Set#divide when passed a block with an arity of > 2" do
  it "only uses the first element if the arity > 2" do
    set = Set["one", "two", "three", "four", "five"].divide do |x, y, z|
      y.should be_nil
      z.should be_nil
      x.length
    end
    set.map { |x| x.to_a.sort }.sort.should == [["five", "four"], ["one", "two"], ["three"]]
  end

  it "only uses the first element if the arity = -1" do
    set = Set["one", "two", "three", "four", "five"].divide do |*xs|
      xs.size.should == 1
      xs.first.length
    end
    set.map { |x| x.to_a.sort }.sort.should == [["five", "four"], ["one", "two"], ["three"]]
  end
end
