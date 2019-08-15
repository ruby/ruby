require_relative '../../spec_helper'

describe "NilClass#dup" do
  it "returns self" do
    nil.dup.should equal(nil)
  end
end
