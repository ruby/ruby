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

  ruby_version_is "2.5" do
    it "does not rescue exception raised in #<=> when compares the given start and end" do
      b = mock('a')
      a = mock('b')
      a.should_receive(:<=>).with(b).and_raise(RangeSpecs::ComparisonError)

      -> { Range.new(a, b) }.should raise_error(RangeSpecs::ComparisonError)
    end
  end

  describe "beginless/endless range" do
    ruby_version_is ""..."2.7" do
      it "does not allow range without left boundary" do
        -> { Range.new(nil, 1) }.should raise_error(ArgumentError, /bad value for range/)
      end
    end

    ruby_version_is "2.7" do
      it "allows beginless left boundary" do
        range = Range.new(nil, 1)
        range.begin.should == nil
      end

      it "distinguishes ranges with included and excluded right boundary" do
        range_exclude = Range.new(nil, 1, true)
        range_include = Range.new(nil, 1, false)

        range_exclude.should_not == range_include
      end
    end

    ruby_version_is ""..."2.6" do
      it "does not allow range without right boundary" do
        -> { Range.new(1, nil) }.should raise_error(ArgumentError, /bad value for range/)
      end
    end

    ruby_version_is "2.6" do
      it "allows endless right boundary" do
        range = Range.new(1, nil)
        range.end.should == nil
      end

      it "distinguishes ranges with included and excluded right boundary" do
        range_exclude = Range.new(1, nil, true)
        range_include = Range.new(1, nil, false)

        range_exclude.should_not == range_include
      end
    end
  end
end
