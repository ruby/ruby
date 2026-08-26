require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Kernel#String" do
  it "is a private method" do
    Kernel.private_instance_methods(false).should.include?(:String)
  end

  it "converts nil to a String" do
    String(nil).should == ""
  end

  it "converts a Float to a String" do
    String(1.12).should == "1.12"
  end

  it "converts a boolean to a String" do
    String(false).should == "false"
    String(true).should == "true"
  end

  it "converts a constant to a String" do
    String(Object).should == "Object"
  end

  it "calls #to_s to convert an arbitrary object to a String" do
    obj = mock('test')
    obj.should_receive(:to_s).and_return("test")

    String(obj).should == "test"
  end

  it "raises a TypeError if #to_s does not exist" do
    obj = mock('to_s')
    class << obj
      undef_method :to_s
    end

    -> { String(obj) }.should.raise(TypeError)
  end

  # #5158
  it "raises a TypeError if respond_to? returns false for #to_s" do
    obj = mock("to_s")
    class << obj
      def respond_to?(meth, include_private=false)
        meth == :to_s ? false : super
      end
    end

    -> { String(obj) }.should.raise(TypeError)
  end

  it "raises a TypeError if #to_s is not defined, even though #respond_to?(:to_s) returns true" do
    # cannot use a mock because of how RSpec affects #method_missing
    obj = Object.new
    class << obj
      undef_method :to_s
      def respond_to?(meth, include_private=false)
        meth == :to_s ? true : super
      end
    end

    -> { String(obj) }.should.raise(TypeError)
  end

  it "calls #to_s if #respond_to?(:to_s) returns true" do
    obj = mock('to_s')
    class << obj
      undef_method :to_s
      def method_missing(meth, *args)
        meth == :to_s ? "test" : super
      end
    end

    String(obj).should == "test"
  end

  it "raises a TypeError if #to_s does not return a String" do
    (obj = mock('123')).should_receive(:to_s).and_return(123)
    -> { String(obj) }.should.raise(TypeError)
  end

  it "returns the same object if it is already a String" do
    string = +"Hello"
    string.should_not_receive(:to_s)
    string2 = String(string)
    string.should.equal?(string2)
  end

  it "returns the same object if it is an instance of a String subclass" do
    subklass = Class.new(String)
    string = subklass.new("Hello")
    string.should_not_receive(:to_s)
    string2 = String(string)
    string.should.equal?(string2)
  end
end

describe "Kernel.String" do
  it "is a public method" do
    Kernel.public_methods(false).should.include?(:String)
  end
end
