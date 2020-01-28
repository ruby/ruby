require_relative '../../spec_helper'
require_relative 'shared/end'

describe "Range#last" do
  it_behaves_like :range_end, :last

  it "returns the specified number of elements from the end" do
    (1..5).last(3).should == [3, 4, 5]
  end

  it "returns an empty array for an empty Range" do
    (0...0).last(2).should == []
  end

  it "returns an empty array when passed zero" do
    (0..2).last(0).should == []
  end

  it "returns all elements in the range when count exceeds the number of elements" do
    (2..4).last(5).should == [2, 3, 4]
  end

  it "raises an ArgumentError when count is negative" do
    -> { (0..2).last(-1) }.should raise_error(ArgumentError)
  end

  it "calls #to_int to convert the argument" do
    obj = mock_int(2)
    (3..7).last(obj).should == [6, 7]
  end

  it "raises a TypeError if #to_int does not return an Integer" do
    obj = mock("to_int")
    obj.should_receive(:to_int).and_return("1")
    -> { (2..3).last(obj) }.should raise_error(TypeError)
  end

  it "truncates the value when passed a Float" do
    (2..9).last(2.8).should == [8, 9]
  end

  it "raises a TypeError when passed nil" do
    -> { (2..3).last(nil) }.should raise_error(TypeError)
  end

  it "raises a TypeError when passed a String" do
    -> { (2..3).last("1") }.should raise_error(TypeError)
  end

  ruby_version_is "2.6" do
    it "raises a RangeError when called on an endless range" do
      -> { eval("(1..)").last }.should raise_error(RangeError)
    end
  end
end
