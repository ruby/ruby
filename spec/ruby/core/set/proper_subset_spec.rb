require_relative '../../spec_helper'
require_relative 'fixtures/set_like'
set_version = defined?(Set::VERSION) ? Set::VERSION : '1.0.0'

describe "Set#proper_subset?" do
  before :each do
    @set = Set[1, 2, 3, 4]
  end

  it "returns true if passed a Set that self is a proper subset of" do
    Set[].proper_subset?(@set).should == true
    Set[].proper_subset?(Set[1, 2, 3]).should == true
    Set[].proper_subset?(Set["a", :b, ?c]).should == true

    Set[1, 2, 3].proper_subset?(@set).should == true
    Set[1, 3].proper_subset?(@set).should == true
    Set[1, 2].proper_subset?(@set).should == true
    Set[1].proper_subset?(@set).should == true

    Set[5].proper_subset?(@set).should == false
    Set[1, 5].proper_subset?(@set).should == false
    Set[nil].proper_subset?(@set).should == false
    Set["test"].proper_subset?(@set).should == false

    @set.proper_subset?(@set).should == false
    Set[].proper_subset?(Set[]).should == false
  end

  it "raises an ArgumentError when passed a non-Set" do
    -> { Set[].proper_subset?([]) }.should.raise(ArgumentError)
    -> { Set[].proper_subset?(1) }.should.raise(ArgumentError)
    -> { Set[].proper_subset?("test") }.should.raise(ArgumentError)
    -> { Set[].proper_subset?(Object.new) }.should.raise(ArgumentError)
  end
end
