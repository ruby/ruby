require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Method#hash" do
  it "needs to be reviewed for spec completeness"

  it "returns the same value for user methods that are eql?" do
    obj = MethodSpecs::Methods.new
    obj.method(:foo).hash.should == obj.method(:bar).hash
  end

  # See also redmine #6048
  it "returns the same value for builtin methods that are eql?" do
    obj = [42]
    obj.method(:to_s).hash.should == obj.method(:inspect).hash
  end
end
