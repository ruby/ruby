require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "UnboundMethod#private?" do
  ruby_version_is "3.1"..."3.2" do
    it "returns false when the method is public" do
      obj = UnboundMethodSpecs::Methods.new
      obj.method(:my_public_method).unbind.private?.should == false
    end

    it "returns false when the method is protected" do
      obj = UnboundMethodSpecs::Methods.new
      obj.method(:my_protected_method).unbind.private?.should == false
    end

    it "returns true when the method is private" do
      obj = UnboundMethodSpecs::Methods.new
      obj.method(:my_private_method).unbind.private?.should == true
    end
  end

  ruby_version_is "3.2" do
    it "has been removed" do
      obj = UnboundMethodSpecs::Methods.new
      obj.method(:my_private_method).unbind.should_not.respond_to?(:private?)
    end
  end
end
