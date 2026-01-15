require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe :string_strip, shared: true do
  it "returns a String in the same encoding as self" do
    " hello ".encode("US-ASCII").send(@method).encoding.should == Encoding::US_ASCII
  end

  it "returns String instances when called on a subclass" do
    StringSpecs::MyString.new(" hello ").send(@method).should be_an_instance_of(String)
    StringSpecs::MyString.new(" ").send(@method).should be_an_instance_of(String)
    StringSpecs::MyString.new("").send(@method).should be_an_instance_of(String)
  end
end
