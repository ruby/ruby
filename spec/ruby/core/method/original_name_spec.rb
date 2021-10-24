require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Method#original_name" do
  it "returns the name of the method" do
    "abc".method(:upcase).original_name.should == :upcase
  end

  it "returns the original name when aliased" do
    obj = MethodSpecs::Methods.new
    obj.method(:foo).original_name.should == :foo
    obj.method(:bar).original_name.should == :foo
    obj.method(:bar).unbind.bind(obj).original_name.should == :foo
  end

  it "returns the original name even when aliased twice" do
    obj = MethodSpecs::Methods.new
    obj.method(:foo).original_name.should == :foo
    obj.method(:baz).original_name.should == :foo
    obj.method(:baz).unbind.bind(obj).original_name.should == :foo
  end
end
