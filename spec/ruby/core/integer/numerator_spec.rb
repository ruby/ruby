require_relative '../../spec_helper'

describe "Integer#numerator" do
  before :all do
    @numbers = [
      0,
      29871,
      99999999999999**99,
      72628191273,
    ].map{|n| [-n, n]}.flatten
  end

  it "returns self" do
    @numbers.each do |number|
      number.numerator.should == number
    end
  end
end
