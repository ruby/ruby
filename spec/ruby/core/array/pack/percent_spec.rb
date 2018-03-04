require_relative '../../../spec_helper'

describe "Array#pack with format '%'" do
  it "raises an Argument Error" do
    lambda { [1].pack("%") }.should raise_error(ArgumentError)
  end
end
