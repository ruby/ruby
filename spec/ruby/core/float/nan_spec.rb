require_relative '../../spec_helper'

describe "Float#nan?" do
  it "returns true if self is not a valid IEEE floating-point number" do
    0.0.should_not.nan?
    -1.5.should_not.nan?
    nan_value.should.nan?
  end
end
