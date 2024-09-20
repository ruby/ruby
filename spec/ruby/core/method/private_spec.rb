require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Method#private?" do
  ruby_version_is "3.1"..."3.2" do
    it "returns false when the method is public" do
      obj = MethodSpecs::Methods.new
      obj.method(:my_public_method).private?.should == false
    end

    it "returns false when the method is protected" do
      obj = MethodSpecs::Methods.new
      obj.method(:my_protected_method).private?.should == false
    end

    it "returns true when the method is private" do
      obj = MethodSpecs::Methods.new
      obj.method(:my_private_method).private?.should == true
    end
  end

  ruby_version_is "3.2" do
    it "has been removed" do
      obj = MethodSpecs::Methods.new
      obj.method(:my_private_method).should_not.respond_to?(:private?)
    end
  end
end
