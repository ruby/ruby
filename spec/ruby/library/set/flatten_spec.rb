require_relative '../../spec_helper'
require_relative 'fixtures/set_like'
require 'set'
set_version = defined?(Set::VERSION) ? Set::VERSION : '1.0.0'

describe "Set#flatten" do
  it "returns a copy of self with each included Set flattened" do
    set = Set[1, 2, Set[3, 4, Set[5, 6, Set[7, 8]]], 9, 10]
    flattened_set = set.flatten

    flattened_set.should_not equal(set)
    flattened_set.should == Set[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  end

  it "raises an ArgumentError when self is recursive" do
    (set = Set[]) << set
    -> { set.flatten }.should raise_error(ArgumentError)
  end

  ruby_version_is ""..."3.5" do
    context "when Set contains a Set-like object" do
      it "returns a copy of self with each included Set-like object flattened" do
        Set[SetSpecs::SetLike.new([1])].flatten.should == Set[1]
      end
    end
  end
end

describe "Set#flatten!" do
  it "flattens self" do
    set = Set[1, 2, Set[3, 4, Set[5, 6, Set[7, 8]]], 9, 10]
    set.flatten!
    set.should == Set[1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
  end

  it "returns self when self was modified" do
    set = Set[1, 2, Set[3, 4]]
    set.flatten!.should equal(set)
  end

  it "returns nil when self was not modified" do
    set = Set[1, 2, 3, 4]
    set.flatten!.should be_nil
  end

  it "raises an ArgumentError when self is recursive" do
    (set = Set[]) << set
    -> { set.flatten! }.should raise_error(ArgumentError)
  end

  version_is(set_version, ""..."1.1.0") do #ruby_version_is ""..."3.3" do
    ruby_version_is ""..."3.5" do
      context "when Set contains a Set-like object" do
        it "flattens self, including Set-like objects" do
          Set[SetSpecs::SetLike.new([1])].flatten!.should == Set[1]
        end
      end
    end
  end
end
