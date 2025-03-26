require_relative '../../../spec_helper'

ruby_version_is '3.3' do
  describe "ObjectSpace::WeakKeyMap#delete" do
    it "removes the entry and returns the deleted value" do
      m = ObjectSpace::WeakKeyMap.new
      key = Object.new
      value = Object.new
      m[key] = value

      m.delete(key).should == value
      m.key?(key).should == false
    end

    it "uses equality semantic" do
      m = ObjectSpace::WeakKeyMap.new
      key = "foo".upcase
      value = Object.new
      m[key] = value

      m.delete("foo".upcase).should == value
      m.key?(key).should == false
    end

    it "calls supplied block if the key is not found" do
      key = Object.new
      m = ObjectSpace::WeakKeyMap.new
      return_value = m.delete(key) do |yielded_key|
        yielded_key.should == key
        5
      end
      return_value.should == 5
    end

    it "returns nil if the key is not found when no block is given" do
      m = ObjectSpace::WeakKeyMap.new
      m.delete(Object.new).should == nil
    end

    it "returns nil when a key cannot be garbage collected" do
      map = ObjectSpace::WeakKeyMap.new

      map.delete(1).should == nil
      map.delete(1.0).should == nil
      map.delete(:a).should == nil
      map.delete(true).should == nil
      map.delete(false).should == nil
      map.delete(nil).should == nil
    end
  end
end
