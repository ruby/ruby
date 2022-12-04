require_relative '../../../spec_helper'

ruby_version_is ""..."3.0" do
  require 'set'

  describe "SortedSet#initialize" do
    it "is private" do
      SortedSet.should have_private_instance_method("initialize")
    end

    it "adds all elements of the passed Enumerable to self" do
      s = SortedSet.new([1, 2, 3])
      s.size.should eql(3)
      s.should include(1)
      s.should include(2)
      s.should include(3)
    end

    it "preprocesses all elements by a passed block before adding to self" do
      s = SortedSet.new([1, 2, 3]) { |x| x * x }
      s.size.should eql(3)
      s.should include(1)
      s.should include(4)
      s.should include(9)
    end

    it "raises on incompatible <=> comparison" do
      # Use #to_a here as elements are sorted only when needed.
      # Therefore the <=> incompatibility is only noticed on sorting.
      -> { SortedSet.new(['00', nil]).to_a }.should raise_error(ArgumentError)
    end
  end
end
