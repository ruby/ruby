require_relative '../../spec_helper'

describe "Array#deconstruct" do
  it "returns self" do
    array = [1]

    array.deconstruct.should equal array
  end
end
