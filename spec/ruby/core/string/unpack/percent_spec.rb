require_relative '../../../spec_helper'

describe "String#unpack with format '%'" do
  it "raises an Argument Error" do
    -> { "abc".unpack("%") }.should raise_error(ArgumentError)
  end
end
