require_relative '../../../spec_helper'

ruby_version_is '3.3' do
  describe "ObjectSpace::WeakMap#delete" do
    it "removes the entry and returns the deleted value" do
      m = ObjectSpace::WeakMap.new
      key = Object.new
      value = Object.new
      m[key] = value

      m.delete(key).should == value
      m.key?(key).should == false
    end

    it "calls supplied block if the key is not found" do
      key = Object.new
      m = ObjectSpace::WeakMap.new
      return_value = m.delete(key) do |yielded_key|
        yielded_key.should == key
        5
      end
      return_value.should == 5
    end

    it "returns nil if the key is not found when no block is given" do
      m = ObjectSpace::WeakMap.new
      m.delete(Object.new).should == nil
    end
  end
end
