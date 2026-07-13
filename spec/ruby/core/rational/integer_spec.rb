require_relative "../../spec_helper"
describe "Rational#integer?" do
  it "returns false for a rational with a numerator and no denominator" do
    Rational(20).integer?.should == false
  end

  it "returns false for a rational with a numerator and a denominator" do
    Rational(20,3).integer?.should == false
  end
end
