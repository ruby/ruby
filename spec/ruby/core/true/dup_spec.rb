require_relative '../../spec_helper'

describe "TrueClass#dup" do
  it "returns self" do
    true.dup.should equal(true)
  end
end
