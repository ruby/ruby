require_relative '../../spec_helper'

describe "TrueClass#inspect" do
  it "is an alias of TrueClass#to_s" do
    true.method(:inspect).should == true.method(:to_s)
  end
end
