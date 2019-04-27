require_relative '../../spec_helper'

describe "Float#dup" do
  it "returns self" do
    float = 2.4
    float.dup.should equal(float)
  end
end
