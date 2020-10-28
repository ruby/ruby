require_relative '../../spec_helper'

describe "Range#initialize" do
  before do
    @range = Range.allocate
  end

  it "is private" do
    Range.should have_private_instance_method("initialize")
  end

  it "initializes correctly the Range object when given 2 arguments" do
    -> { @range.send(:initialize, 0, 1) }.should_not raise_error
  end

  it "initializes correctly the Range object when given 3 arguments" do
    -> { @range.send(:initialize, 0, 1, true) }.should_not raise_error
  end

  it "raises an ArgumentError if passed without or with only one argument" do
    -> { @range.send(:initialize) }.should raise_error(ArgumentError)
    -> { @range.send(:initialize, 1) }.should raise_error(ArgumentError)
  end

  it "raises an ArgumentError if passed with four or more arguments" do
    -> { @range.send(:initialize, 1, 3, 5, 7) }.should raise_error(ArgumentError)
    -> { @range.send(:initialize, 1, 3, 5, 7, 9) }.should raise_error(ArgumentError)
  end

  ruby_version_is ""..."3.0" do
    it "raises a NameError if called on an already initialized Range" do
      -> { (0..1).send(:initialize, 1, 3) }.should raise_error(NameError)
      -> { (0..1).send(:initialize, 1, 3, true) }.should raise_error(NameError)
    end
  end

  ruby_version_is "3.0" do
    it "raises a FrozenError if called on an already initialized Range" do
      -> { (0..1).send(:initialize, 1, 3) }.should raise_error(FrozenError)
      -> { (0..1).send(:initialize, 1, 3, true) }.should raise_error(FrozenError)
    end
  end

  it "raises an ArgumentError if arguments don't respond to <=>" do
    o1 = Object.new
    o2 = Object.new

    -> { @range.send(:initialize, o1, o2) }.should raise_error(ArgumentError)
  end
end
