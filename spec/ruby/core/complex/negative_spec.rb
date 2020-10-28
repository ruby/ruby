require_relative '../../spec_helper'

describe "Complex#negative?" do
  it "is undefined" do
    c = Complex(1)

    c.methods.should_not include(:negative?)

    -> {
      c.negative?
    }.should raise_error(NoMethodError)
  end
end
