require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "UnboundMethod#original_name" do
  it "returns the name of the method" do
    String.instance_method(:upcase).original_name.should == :upcase
  end

  it "returns the original name" do
    obj = UnboundMethodSpecs::Methods.new
    obj.method(:foo).unbind.original_name.should == :foo
    obj.method(:bar).unbind.original_name.should == :foo
    UnboundMethodSpecs::Methods.instance_method(:bar).original_name.should == :foo
  end

  it "returns the original name even when aliased twice" do
    obj = UnboundMethodSpecs::Methods.new
    obj.method(:foo).unbind.original_name.should == :foo
    obj.method(:baz).unbind.original_name.should == :foo
    UnboundMethodSpecs::Methods.instance_method(:baz).original_name.should == :foo
  end
end
