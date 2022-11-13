require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "3.1"..."3.2" do
  describe "Method#protected?" do
    it "returns false when the method is public" do
      obj = MethodSpecs::Methods.new
      obj.method(:my_public_method).protected?.should == false
    end

    it "returns true when the method is protected" do
      obj = MethodSpecs::Methods.new
      obj.method(:my_protected_method).protected?.should == true
    end

    it "returns false when the method is private" do
      obj = MethodSpecs::Methods.new
      obj.method(:my_private_method).protected?.should == false
    end
  end
end
