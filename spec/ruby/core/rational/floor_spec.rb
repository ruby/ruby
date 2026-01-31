require_relative "../../spec_helper"
require_relative "../integer/shared/integer_floor_precision"

describe "Rational#floor" do
  context "with values equal to integers" do
    it_behaves_like :integer_floor_precision, :Rational
  end

  before do
    @rational = Rational(2200, 7)
  end

  describe "with no arguments (precision = 0)" do

    it "returns the Integer value rounded toward negative infinity" do
      @rational.floor.should eql 314

      Rational(1, 2).floor.should eql 0
      Rational(-1, 2).floor.should eql(-1)
      Rational(1, 1).floor.should eql 1
    end
  end

  describe "with a precision < 0" do
    it "moves the rounding point n decimal places left, returning an Integer" do
      @rational.floor(-3).should eql 0
      @rational.floor(-2).should eql 300
      @rational.floor(-1).should eql 310

      Rational(100, 2).floor(-1).should eql 50
      Rational(100, 2).floor(-2).should eql 0
      Rational(-100, 2).floor(-1).should eql(-50)
      Rational(-100, 2).floor(-2).should eql(-100)
    end
  end

  describe "with a precision > 0" do
    it "moves the rounding point n decimal places right, returning a Rational" do
      @rational.floor(1).should eql Rational(1571, 5)
      @rational.floor(2).should eql Rational(7857, 25)
      @rational.floor(3).should eql Rational(62857, 200)

      Rational(100, 2).floor(1).should eql Rational(50, 1)
      Rational(100, 2).floor(2).should eql Rational(50, 1)
      Rational(-100, 2).floor(1).should eql Rational(-50, 1)
      Rational(-100, 2).floor(2).should eql Rational(-50, 1)
    end
  end
end
