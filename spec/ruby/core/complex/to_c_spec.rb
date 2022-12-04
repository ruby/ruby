require_relative '../../spec_helper'

describe "Complex#to_c" do
  it "returns self" do
    value = Complex(1, 5)
    value.to_c.should equal(value)
  end

  it 'returns the same value' do
    Complex(1, 5).to_c.should == Complex(1, 5)
  end
end
