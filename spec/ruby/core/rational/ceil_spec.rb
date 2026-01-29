require_relative "../../spec_helper"
require_relative "../integer/shared/integer_ceil_precision"

describe "Rational#ceil" do
  context "with values equal to integers" do
    it_behaves_like :integer_ceil_precision, :Rational
  end

  before do
    @rational = Rational(2200, 7)
  end

  describe "with no arguments (precision = 0)" do
    it "returns the Integer value rounded toward positive infinity" do
      @rational.ceil.should eql 315

      Rational(1, 2).ceil.should eql 1
      Rational(-1, 2).ceil.should eql 0
      Rational(1, 1).ceil.should eql 1
    end
  end

  describe "with a precision < 0" do
    it "moves the rounding point n decimal places left, returning an Integer" do
      @rational.ceil(-3).should eql 1000
      @rational.ceil(-2).should eql 400
      @rational.ceil(-1).should eql 320

      Rational(100, 2).ceil(-1).should eql 50
      Rational(100, 2).ceil(-2).should eql 100
      Rational(-100, 2).ceil(-1).should eql(-50)
      Rational(-100, 2).ceil(-2).should eql(0)
    end
  end

  describe "with precision > 0" do
    it "moves the rounding point n decimal places right, returning a Rational" do
      @rational.ceil(1).should eql Rational(3143, 10)
      @rational.ceil(2).should eql Rational(31429, 100)
      @rational.ceil(3).should eql Rational(157143, 500)

      Rational(100, 2).ceil(1).should eql Rational(50, 1)
      Rational(100, 2).ceil(2).should eql Rational(50, 1)
      Rational(-100, 2).ceil(1).should eql Rational(-50, 1)
      Rational(-100, 2).ceil(2).should eql Rational(-50, 1)
    end
  end
end
