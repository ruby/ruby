require_relative '../../spec_helper'

describe "NilClass#to_a" do
  it "returns an empty array" do
    nil.to_a.should == []
  end
end
