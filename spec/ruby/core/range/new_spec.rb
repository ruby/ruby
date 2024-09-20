require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Range.new" do
  it "constructs a range using the given start and end" do
    range = Range.new('a', 'c')
    range.should == ('a'..'c')

    range.first.should == 'a'
    range.last.should == 'c'
  end

  it "includes the end object when the third parameter is omitted or false" do
    Range.new('a', 'c').to_a.should == ['a', 'b', 'c']
    Range.new(1, 3).to_a.should == [1, 2, 3]

    Range.new('a', 'c', false).to_a.should == ['a', 'b', 'c']
    Range.new(1, 3, false).to_a.should == [1, 2, 3]

    Range.new('a', 'c', true).to_a.should == ['a', 'b']
    Range.new(1, 3, 1).to_a.should == [1, 2]

    Range.new(1, 3, mock('[1,2]')).to_a.should == [1, 2]
    Range.new(1, 3, :test).to_a.should == [1, 2]
  end

  it "raises an ArgumentError when the given start and end can't be compared by using #<=>" do
    -> { Range.new(1, mock('x'))         }.should raise_error(ArgumentError)
    -> { Range.new(mock('x'), mock('y')) }.should raise_error(ArgumentError)

    b = mock('x')
    (a = mock('nil')).should_receive(:<=>).with(b).and_return(nil)
    -> { Range.new(a, b) }.should raise_error(ArgumentError)
  end

  it "does not rescue exception raised in #<=> when compares the given start and end" do
    b = mock('a')
    a = mock('b')
    a.should_receive(:<=>).with(b).and_raise(RangeSpecs::ComparisonError)

    -> { Range.new(a, b) }.should raise_error(RangeSpecs::ComparisonError)
  end

  describe "beginless/endless range" do
    it "allows beginless left boundary" do
      range = Range.new(nil, 1)
      range.begin.should == nil
    end

    it "distinguishes ranges with included and excluded right boundary" do
      range_exclude = Range.new(nil, 1, true)
      range_include = Range.new(nil, 1, false)

      range_exclude.should_not == range_include
    end

    it "allows endless right boundary" do
      range = Range.new(1, nil)
      range.end.should == nil
    end

    it "distinguishes ranges with included and excluded right boundary" do
      range_exclude = Range.new(1, nil, true)
      range_include = Range.new(1, nil, false)

      range_exclude.should_not == range_include
    end

    it "creates a frozen range if the class is Range.class" do
      Range.new(1, 2).should.frozen?
    end

    it "does not create a frozen range if the class is not Range.class" do
      Class.new(Range).new(1, 2).should_not.frozen?
    end
  end
end
