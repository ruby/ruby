require_relative '../../spec_helper'

describe "FalseClass#dup" do
  it "returns self" do
    false.dup.should equal(false)
  end
end
