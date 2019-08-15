require_relative '../../spec_helper'

describe "Numeric#finite?" do
  it "returns true by default" do
    o = mock_numeric("finite")
    o.finite?.should be_true
  end
end
