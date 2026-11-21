require_relative '../../spec_helper'

describe "Set#include?" do
  it "returns true when self contains the passed Object" do
    set = Set[:a, :b, :c]
    set.include?(:a).should == true
    set.include?(:e).should == false
  end

  describe "member equality" do
    it "is checked using both #hash and #eql?" do
      obj = Object.new
      obj_another = Object.new

      def obj.hash; 42 end
      def obj_another.hash; 42 end
      def obj_another.eql?(o) hash == o.hash end

      set = Set["a", "b", "c", obj]
      set.include?(obj_another).should == true
    end

    it "is not checked using #==" do
      obj = Object.new
      set = Set["a", "b", "c"]

      obj.should_not_receive(:==)
      set.include?(obj)
    end
  end
end
