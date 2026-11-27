require_relative '../../spec_helper'

describe "NilClass#^" do
  it "is an alias of NilClass#|" do
    nil.method(:^).should == nil.method(:|)
  end
end
