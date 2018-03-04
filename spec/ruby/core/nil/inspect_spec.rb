require_relative '../../spec_helper'

describe "NilClass#inspect" do
  it "returns the string 'nil'" do
    nil.inspect.should == "nil"
  end
end
