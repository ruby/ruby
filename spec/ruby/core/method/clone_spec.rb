require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Method#clone" do
  it "returns a copy of the method" do
    m1 = MethodSpecs::Methods.new.method(:foo)
    m2 = m1.clone

    m1.should == m2
    m1.should_not equal(m2)

    m1.call.should == m2.call
  end
end
