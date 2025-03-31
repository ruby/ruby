require_relative '../../../spec_helper'

ruby_version_is '3.3' do
  describe "ObjectSpace::WeakKeyMap#clear" do
    it "removes all the entries" do
      m = ObjectSpace::WeakKeyMap.new

      key = Object.new
      value = Object.new
      m[key] = value

      key2 = Object.new
      value2 = Object.new
      m[key2] = value2

      m.clear

      m.key?(key).should == false
      m.key?(key2).should == false
    end

    it "returns self" do
      m = ObjectSpace::WeakKeyMap.new
      m.clear.should.equal?(m)
    end
  end
end
