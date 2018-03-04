require_relative '../../spec_helper'

describe "NilClass#to_c" do
  it "returns Complex(0, 0)" do
    nil.to_c.should eql(Complex(0, 0))
  end
end
