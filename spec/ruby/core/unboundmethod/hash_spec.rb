require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "UnboundMethod#hash" do
  it "returns the same value for user methods that are eql?" do
    foo, bar = UnboundMethodSpecs::Methods.instance_method(:foo), UnboundMethodSpecs::Methods.instance_method(:bar)
    foo.hash.should == bar.hash
  end

  # See also redmine #6048
  it "returns the same value for builtin methods that are eql?" do
    to_s, inspect = Array.instance_method(:to_s), Array.instance_method(:inspect)
    to_s.hash.should == inspect.hash
  end

  it "equals a hash of the same method in the superclass" do
    foo_in_superclass = UnboundMethodSpecs::HashSpecs::SuperClass.instance_method(:foo)
    foo = UnboundMethodSpecs::HashSpecs::SubClass.instance_method(:foo)

    foo.hash.should == foo_in_superclass.hash
  end
end
