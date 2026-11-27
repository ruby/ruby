require_relative "../../spec_helper"

describe "Set#to_s" do
  it "returns a String representation of self" do
    Set[].to_s.should.is_a?(String)
    Set[nil, false, true].to_s.should.is_a?(String)
    Set[1, 2, 3].to_s.should.is_a?(String)
    Set["1", "2", "3"].to_s.should.is_a?(String)
    Set[:a, "b", Set[?c]].to_s.should.is_a?(String)
  end

  ruby_version_is "4.0" do
    it "does include the elements of the set" do
      Set["1"].to_s.should == 'Set["1"]'
    end
  end

  ruby_version_is ""..."4.0" do
    it "does include the elements of the set" do
      Set["1"].to_s.should == '#<Set: {"1"}>'
    end
  end

  it "puts spaces between the elements" do
    Set["1", "2"].to_s.should.include?('", "')
  end

  ruby_version_is "4.0" do
    it "correctly handles cyclic-references" do
      set1 = Set[]
      set2 = Set[set1]
      set1 << set2
      set1.to_s.should.is_a?(String)
      set1.to_s.should.include?("Set[...]")
    end
  end

  ruby_version_is ""..."4.0" do
    it "correctly handles cyclic-references" do
      set1 = Set[]
      set2 = Set[set1]
      set1 << set2
      set1.to_s.should.is_a?(String)
      set1.to_s.should.include?("#<Set: {...}>")
    end
  end
end
