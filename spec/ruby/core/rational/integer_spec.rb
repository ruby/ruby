require_relative "../../spec_helper"
describe "Rational#integer?" do
  # Guard against the Mathn library
  guard -> { !defined?(Math.rsqrt) } do
    it "returns false for a rational with a numerator and no denominator" do
      Rational(20).integer?.should be_false
    end
  end

  it "returns false for a rational with a numerator and a denominator" do
    Rational(20,3).integer?.should be_false
  end
end
