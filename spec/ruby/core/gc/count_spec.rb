require_relative '../../spec_helper'

describe "GC.count" do
  it "returns an integer" do
    GC.count.should be_kind_of(Integer)
  end
end
