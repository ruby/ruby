require_relative '../../spec_helper'

ruby_version_is "4.1" do
  describe "Set#compact" do
    it "deletes the nil element from the set" do
      set = Set[1, 2, nil, false]
      set.compact.should == Set[1, 2, false]
    end

    it "does not alter the set it is called on" do
      set = Set[1, 2, nil, false]
      set.compact
      set.should == Set[1, 2, nil, false]
    end

    it "duplicates the set if no nil is present" do
      set = Set[1, 2, false]
      set.compact.should_not equal(set)
    end

    it "ignores frozen status" do
      set = Set[1, 2, nil, false].freeze
      set.compact.should_not.frozen?
    end
  end

  describe "Set#compact!" do
    it "deletes the nil element from the set" do
      set = Set[1, 2, nil, false]
      set.compact!.should == Set[1, 2, false]
      set.should == Set[1, 2, false]
    end

    it "returns nil if the set did not contain a nil" do
      set = Set[1, 2, false]
      set.compact!.should be_nil
    end

    it "raises a FrozenError if called on a frozen set" do
      set = Set[1, 2, nil, false].freeze
      -> { set.compact! }.should raise_error(FrozenError, /can't modify frozen Set/)
    end
  end
end
