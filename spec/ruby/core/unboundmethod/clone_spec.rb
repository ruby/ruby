require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "UnboundMethod#clone" do
  it "returns a copy of the UnboundMethod" do
    um1 = UnboundMethodSpecs::Methods.instance_method(:foo)
    um2 = um1.clone

    (um1 == um2).should == true
    um1.bind(UnboundMethodSpecs::Methods.new).call.should == um2.bind(UnboundMethodSpecs::Methods.new).call
  end
end
