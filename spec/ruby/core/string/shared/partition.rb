require_relative '../../../spec_helper'
require_relative '../fixtures/classes'

describe :string_partition, shared: true do
  it "returns String instances when called on a subclass" do
    StringSpecs::MyString.new("hello").send(@method, "l").each do |item|
      item.should be_an_instance_of(String)
    end

    StringSpecs::MyString.new("hello").send(@method, "x").each do |item|
      item.should be_an_instance_of(String)
    end

    StringSpecs::MyString.new("hello").send(@method, /l./).each do |item|
      item.should be_an_instance_of(String)
    end
  end

  it "returns before- and after- parts in the same encoding as self" do
    strings = "hello".encode("US-ASCII").send(@method, "ello")
    strings[0].encoding.should == Encoding::US_ASCII
    strings[2].encoding.should == Encoding::US_ASCII

    strings = "hello".encode("US-ASCII").send(@method, /ello/)
    strings[0].encoding.should == Encoding::US_ASCII
    strings[2].encoding.should == Encoding::US_ASCII
  end

  it "returns the matching part in the separator's encoding" do
    strings = "hello".encode("US-ASCII").send(@method, "ello")
    strings[1].encoding.should == Encoding::UTF_8
  end
end
