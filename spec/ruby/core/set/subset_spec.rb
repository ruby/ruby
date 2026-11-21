require_relative '../../spec_helper'
require_relative 'fixtures/set_like'
set_version = defined?(Set::VERSION) ? Set::VERSION : '1.0.0'

describe "Set#subset?" do
  before :each do
    @set = Set[1, 2, 3, 4]
  end

  it "returns true if passed a Set that is equal to self or self is a subset of" do
    @set.subset?(@set).should == true
    Set[].subset?(Set[]).should == true

    Set[].subset?(@set).should == true
    Set[].subset?(Set[1, 2, 3]).should == true
    Set[].subset?(Set["a", :b, ?c]).should == true

    Set[1, 2, 3].subset?(@set).should == true
    Set[1, 3].subset?(@set).should == true
    Set[1, 2].subset?(@set).should == true
    Set[1].subset?(@set).should == true

    Set[5].subset?(@set).should == false
    Set[1, 5].subset?(@set).should == false
    Set[nil].subset?(@set).should == false
    Set["test"].subset?(@set).should == false
  end

  it "raises an ArgumentError when passed a non-Set" do
    -> { Set[].subset?([]) }.should.raise(ArgumentError)
    -> { Set[].subset?(1) }.should.raise(ArgumentError)
    -> { Set[].subset?("test") }.should.raise(ArgumentError)
    -> { Set[].subset?(Object.new) }.should.raise(ArgumentError)
  end
end
