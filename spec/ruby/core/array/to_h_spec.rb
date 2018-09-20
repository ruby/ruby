require_relative '../../spec_helper'
require_relative 'fixtures/classes'

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
    lambda { [:x].to_h }.should raise_error(TypeError)
  end

  it "raises ArgumentError if an element is not a [key, value] pair" do
    lambda { [[:x]].to_h }.should raise_error(ArgumentError)
  end

  it "does not accept arguments" do
    lambda { [].to_h(:a, :b) }.should raise_error(ArgumentError)
  end

  ruby_version_is "2.6" do
    it "converts [key, value] pairs returned by the block to a hash" do
      i = 0
      [:a, :b].to_h {|k| [k, i += 1]}.should == { a: 1, b: 2 }
    end
  end
end
