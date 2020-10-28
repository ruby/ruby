require_relative '../../spec_helper'

describe "Float#zero?" do
  it "returns true if self is 0.0" do
    0.0.should.zero?
    1.0.should_not.zero?
    -1.0.should_not.zero?
  end
end
