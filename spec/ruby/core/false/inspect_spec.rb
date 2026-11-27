require_relative '../../spec_helper'

describe "FalseClass#inspect" do
  it "is an alias of FalseClass#to_s" do
    false.method(:inspect).should == false.method(:to_s)
  end
end
