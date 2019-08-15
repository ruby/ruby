require_relative '../../spec_helper'

describe "TrueClass#inspect" do
  it "returns the string 'true'" do
    true.inspect.should == "true"
  end
end
