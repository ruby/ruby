require_relative '../../spec_helper'
require_relative 'fixtures/set_like'
require 'set'
set_version = defined?(Set::VERSION) ? Set::VERSION : '1.0.0'

describe "Set#subset?" do
  before :each do
    @set = Set[1, 2, 3, 4]
  end

  it "returns true if passed a Set that is equal to self or self is a subset of" do
    @set.subset?(@set).should be_true
    Set[].subset?(Set[]).should be_true

    Set[].subset?(@set).should be_true
    Set[].subset?(Set[1, 2, 3]).should be_true
    Set[].subset?(Set["a", :b, ?c]).should be_true

    Set[1, 2, 3].subset?(@set).should be_true
    Set[1, 3].subset?(@set).should be_true
    Set[1, 2].subset?(@set).should be_true
    Set[1].subset?(@set).should be_true

    Set[5].subset?(@set).should be_false
    Set[1, 5].subset?(@set).should be_false
    Set[nil].subset?(@set).should be_false
    Set["test"].subset?(@set).should be_false
  end

  it "raises an ArgumentError when passed a non-Set" do
    -> { Set[].subset?([]) }.should raise_error(ArgumentError)
    -> { Set[].subset?(1) }.should raise_error(ArgumentError)
    -> { Set[].subset?("test") }.should raise_error(ArgumentError)
    -> { Set[].subset?(Object.new) }.should raise_error(ArgumentError)
  end

  version_is(set_version, ""..."1.1.0") do #ruby_version_is ""..."3.3" do
    context "when comparing to a Set-like object" do
      it "returns true if passed a Set-like object that self is a subset of" do
        Set[1, 2, 3].subset?(SetSpecs::SetLike.new([1, 2, 3, 4])).should be_true
      end
    end
  end
end
