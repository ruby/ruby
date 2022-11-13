require_relative '../../spec_helper'
require_relative 'fixtures/classes'

ruby_version_is "3.1"..."3.2" do
  describe "UnboundMethod#private?" do
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
end
