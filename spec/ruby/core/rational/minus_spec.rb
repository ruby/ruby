require_relative '../../spec_helper'
require_relative '../../shared/rational/arithmetic_exception_in_coerce'

describe "Rational#-" do
  it_behaves_like :rational_arithmetic_exception_in_coerce, :-

  it "calls #coerce on the passed argument with self" do
    rational = Rational(3, 4)
    obj = mock("Object")
    obj.should_receive(:coerce).with(rational).and_return([1, 2])

    rational - obj
  end

  it "calls #- on the coerced Rational with the coerced Object" do
    rational = Rational(3, 4)

    coerced_rational = mock("Coerced Rational")
    coerced_rational.should_receive(:-).and_return(:result)

    coerced_obj = mock("Coerced Object")

    obj = mock("Object")
    obj.should_receive(:coerce).and_return([coerced_rational, coerced_obj])

    (rational - obj).should == :result
  end
end

describe "Rational#- passed a Rational" do
  it "returns the result of subtracting other from self as a Rational" do
    (Rational(3, 4) - Rational(0, 1)).should eql(Rational(3, 4))
    (Rational(3, 4) - Rational(1, 4)).should eql(Rational(1, 2))

    (Rational(3, 4) - Rational(2, 1)).should eql(Rational(-5, 4))
  end
end

describe "Rational#- passed a Float" do
  it "returns the result of subtracting other from self as a Float" do
    (Rational(3, 4) - 0.2).should eql(0.55)
    (Rational(3, 4) - 2.5).should eql(-1.75)
  end
end

describe "Rational#- passed an Integer" do
  it "returns the result of subtracting other from self as a Rational" do
    (Rational(3, 4) - 1).should eql(Rational(-1, 4))
    (Rational(3, 4) - 2).should eql(Rational(-5, 4))
  end
end
