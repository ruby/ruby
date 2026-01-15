require_relative "../../spec_helper"
require_relative 'fixtures/rational'

describe "Rational#<=> when passed a Rational object" do
  it "returns 1 when self is greater than the passed argument" do
    (Rational(4, 4) <=> Rational(3, 4)).should equal(1)
    (Rational(-3, 4) <=> Rational(-4, 4)).should equal(1)
  end

  it "returns 0 when self is equal to the passed argument" do
    (Rational(4, 4) <=> Rational(4, 4)).should equal(0)
    (Rational(-3, 4) <=> Rational(-3, 4)).should equal(0)
  end

  it "returns -1 when self is less than the passed argument" do
    (Rational(3, 4) <=> Rational(4, 4)).should equal(-1)
    (Rational(-4, 4) <=> Rational(-3, 4)).should equal(-1)
  end
end

describe "Rational#<=> when passed an Integer object" do
  it "returns 1 when self is greater than the passed argument" do
    (Rational(4, 4) <=> 0).should equal(1)
    (Rational(4, 4) <=> -10).should equal(1)
    (Rational(-3, 4) <=> -1).should equal(1)
  end

  it "returns 0 when self is equal to the passed argument" do
    (Rational(4, 4) <=> 1).should equal(0)
    (Rational(-8, 4) <=> -2).should equal(0)
  end

  it "returns -1 when self is less than the passed argument" do
    (Rational(3, 4) <=> 1).should equal(-1)
    (Rational(-4, 4) <=> 0).should equal(-1)
  end
end

describe "Rational#<=> when passed a Float object" do
  it "returns 1 when self is greater than the passed argument" do
    (Rational(4, 4) <=> 0.5).should equal(1)
    (Rational(4, 4) <=> -1.5).should equal(1)
    (Rational(-3, 4) <=> -0.8).should equal(1)
  end

  it "returns 0 when self is equal to the passed argument" do
    (Rational(4, 4) <=> 1.0).should equal(0)
    (Rational(-6, 4) <=> -1.5).should equal(0)
  end

  it "returns -1 when self is less than the passed argument" do
    (Rational(3, 4) <=> 1.2).should equal(-1)
    (Rational(-4, 4) <=> 0.5).should equal(-1)
  end
end

describe "Rational#<=> when passed an Object that responds to #coerce" do
  it "calls #coerce on the passed argument with self" do
    rational = Rational(3, 4)

    obj = mock("Object")
    obj.should_receive(:coerce).with(rational).and_return([1, 2])

    rational <=> obj
  end

  it "calls #<=> on the coerced Rational with the coerced Object" do
    rational = Rational(3, 4)

    coerced_rational = mock("Coerced Rational")
    coerced_rational.should_receive(:<=>).and_return(:result)

    coerced_obj = mock("Coerced Object")

    obj = mock("Object")
    obj.should_receive(:coerce).and_return([coerced_rational, coerced_obj])

    (rational <=> obj).should == :result
  end

  it "does not rescue exception raised in other#coerce" do
    b = mock("numeric with failed #coerce")
    b.should_receive(:coerce).and_raise(RationalSpecs::CoerceError)

    -> { Rational(3, 4) <=> b }.should raise_error(RationalSpecs::CoerceError)
  end
end

describe "Rational#<=> when passed a non-Numeric Object that doesn't respond to #coerce" do
  it "returns nil" do
    (Rational <=> mock("Object")).should be_nil
  end
end
