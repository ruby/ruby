require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/iterable_and_tolerating_size_increasing'

describe "Array#to_h" do
  it "converts empty array to empty hash" do
    [].to_h.should == {}
  end

  it "converts [key, value] pairs to a hash" do
    hash = [[:a, 1], [:b, 2]].to_h
    hash.should == { a: 1, b: 2 }
  end

  it "uses the last value of a duplicated key" do
    hash = [[:a, 1], [:b, 2], [:a, 3]].to_h
    hash.should == { a: 3, b: 2 }
  end

  it "calls #to_ary on contents" do
    pair = mock('to_ary')
    pair.should_receive(:to_ary).and_return([:b, 2])
    hash = [[:a, 1], pair].to_h
    hash.should == { a: 1, b: 2 }
  end

  it "raises TypeError if an element is not an array" do
    -> { [:x].to_h }.should raise_error(TypeError)
  end

  it "raises ArgumentError if an element is not a [key, value] pair" do
    -> { [[:x]].to_h }.should raise_error(ArgumentError)
  end

  it "does not accept arguments" do
    -> { [].to_h(:a, :b) }.should raise_error(ArgumentError)
  end

  it "produces a hash that returns nil for a missing element" do
    [[:a, 1], [:b, 2]].to_h[:c].should be_nil
  end

  context "with block" do
    it "converts [key, value] pairs returned by the block to a Hash" do
      [:a, :b].to_h { |k| [k, k.to_s] }.should == { a: 'a', b: 'b' }
    end

    it "raises ArgumentError if block returns longer or shorter array" do
      -> do
        [:a, :b].to_h { |k| [k, k.to_s, 1] }
      end.should raise_error(ArgumentError, /wrong array length at 0/)

      -> do
        [:a, :b].to_h { |k| [k] }
      end.should raise_error(ArgumentError, /wrong array length at 0/)
    end

    it "raises TypeError if block returns something other than Array" do
      -> do
        [:a, :b].to_h { |k| "not-array" }
      end.should raise_error(TypeError, /wrong element type String at 0/)
    end

    it "coerces returned pair to Array with #to_ary" do
      x = mock('x')
      x.stub!(:to_ary).and_return([:b, 'b'])

      [:a].to_h { |k| x }.should == { :b => 'b' }
    end

    it "does not coerce returned pair to Array with #to_a" do
      x = mock('x')
      x.stub!(:to_a).and_return([:b, 'b'])

      -> do
        [:a].to_h { |k| x }
      end.should raise_error(TypeError, /wrong element type MockObject at 0/)
    end
  end
end

describe "Array#to_h" do
  @value_to_return = -> e { [e, e.to_s] }
  it_behaves_like :array_iterable_and_tolerating_size_increasing, :to_h
end
