require_relative '../../spec_helper'
require_relative 'fixtures/classes'
require_relative 'shared/enumerable_enumeratorized'

describe "Enumerable#slice_before" do
  before :each do
    @enum = EnumerableSpecs::Numerous.new(7,6,5,4,3,2,1)
  end

  describe "when given an argument and no block" do
    it "calls === on the argument to determine when to yield" do
      arg = mock "filter"
      arg.should_receive(:===).and_return(false, true, false, false, false, true, false)
      e = @enum.slice_before(arg)
      e.should be_an_instance_of(Enumerator)
      e.to_a.should == [[7], [6, 5, 4, 3], [2, 1]]
    end

    it "doesn't yield an empty array if the filter matches the first entry or the last entry" do
      arg = mock "filter"
      arg.should_receive(:===).and_return(true).exactly(7)
      e = @enum.slice_before(arg)
      e.to_a.should == [[7], [6], [5], [4], [3], [2], [1]]
    end

    it "uses standard boolean as a test" do
      arg = mock "filter"
      arg.should_receive(:===).and_return(false, :foo, nil, false, false, 42, false)
      e = @enum.slice_before(arg)
      e.to_a.should == [[7], [6, 5, 4, 3], [2, 1]]
    end
  end

  describe "when given a block" do
    describe "and no argument" do
      it "calls the block to determine when to yield" do
        e = @enum.slice_before{|i| i == 6 || i == 2}
        e.should be_an_instance_of(Enumerator)
        e.to_a.should == [[7], [6, 5, 4, 3], [2, 1]]
      end
    end

    it "does not accept arguments" do
      lambda {
        @enum.slice_before(1) {}
      }.should raise_error(ArgumentError)
    end
  end

  it "raises an ArgumentError when given an incorrect number of arguments" do
    lambda { @enum.slice_before("one", "two") }.should raise_error(ArgumentError)
    lambda { @enum.slice_before }.should raise_error(ArgumentError)
  end

  describe "when an iterator method yields more than one value" do
    it "processes all yielded values" do
      enum = EnumerableSpecs::YieldsMulti.new
      result = enum.slice_before { |i| i == [3, 4, 5] }.to_a
      result.should == [[[1, 2]], [[3, 4, 5], [6, 7, 8, 9]]]
    end
  end

  it_behaves_like :enumerable_enumeratorized_with_unknown_size, [:slice_before, 3]
end
