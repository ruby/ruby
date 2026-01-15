require_relative '../../spec_helper'
require_relative '../enumerable/fixtures/classes'

describe "Enumerable#to_set" do
  it "returns a new Set created from self" do
    (1..4).to_set.should == Set[1, 2, 3, 4]
    (1...4).to_set.should == Set[1, 2, 3]
  end

  it "passes down passed blocks" do
    (1..3).to_set { |x| x * x }.should == Set[1, 4, 9]
  end

  ruby_version_is "4.0" do
    it "raises a RangeError if the range is infinite" do
      -> { (1..).to_set }.should raise_error(RangeError, "cannot convert endless range to a set")
      -> { (1...).to_set }.should raise_error(RangeError, "cannot convert endless range to a set")
    end
  end

  ruby_version_is ""..."4.0" do
    it "instantiates an object of provided as the first argument set class" do
      set = (1..3).to_set(EnumerableSpecs::SetSubclass)
      set.should be_kind_of(EnumerableSpecs::SetSubclass)
      set.to_a.sort.should == [1, 2, 3]
    end
  end

  ruby_version_is "4.0"..."4.1" do
    it "instantiates an object of provided as the first argument set class and warns" do
      set = nil
      proc {
        set = (1..3).to_set(EnumerableSpecs::SetSubclass)
      }.should complain(/Enumerable#to_set/)
      set.should be_kind_of(EnumerableSpecs::SetSubclass)
      set.to_a.sort.should == [1, 2, 3]
    end
  end

  ruby_version_is "4.1" do
    it "does not accept any positional argument" do
      -> {
        (1..3).to_set(EnumerableSpecs::SetSubclass)
      }.should raise_error(ArgumentError, 'wrong number of arguments (given 1, expected 0)')
    end
  end

  it "does not need explicit `require 'set'`" do
    output = ruby_exe(<<~RUBY, options: '--disable-gems', args: '2>&1')
      puts (1..3).to_set.to_a.inspect
    RUBY

    output.chomp.should == "[1, 2, 3]"
  end
end
