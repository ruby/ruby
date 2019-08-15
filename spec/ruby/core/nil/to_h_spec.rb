require_relative '../../spec_helper'

describe "NilClass#to_h" do
  it "returns an empty hash" do
    nil.to_h.should == {}
    nil.to_h.default.should == nil
  end
end
