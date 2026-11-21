require_relative '../../spec_helper'
require_relative 'fixtures/coerce'
require_relative 'shared/arithmetic_exception_in_coerce'

describe "Float#/" do
  it_behaves_like :float_arithmetic_exception_in_coerce, :/

  it "returns self divided by other" do
    (5.75 / -2).should be_close(-2.875,TOLERANCE)
    (451.0 / 9.3).should be_close(48.494623655914,TOLERANCE)
    (91.1 / -0xffffffff).should be_close(-2.12108716418061e-08, TOLERANCE)
  end

  it "properly coerces objects" do
    (5.0 / FloatSpecs::CanCoerce.new(5)).should be_close(0, TOLERANCE)
  end

  it "returns +Infinity when dividing non-zero by zero of the same sign" do
    (1.0 / 0.0).should.infinite? == 1
    (-1.0 / -0.0).should.infinite? == 1
  end

  it "returns -Infinity when dividing non-zero by zero of opposite sign" do
    (-1.0 / 0.0).should.infinite? == -1
    (1.0 / -0.0).should.infinite? == -1
  end

  it "returns NaN when dividing zero by zero" do
    (0.0 / 0.0).should.nan?
    (-0.0 / 0.0).should.nan?
    (0.0 / -0.0).should.nan?
    (-0.0 / -0.0).should.nan?
  end

  it "raises a TypeError when given a non-Numeric" do
    -> { 13.0 / "10"    }.should.raise(TypeError)
    -> { 13.0 / :symbol }.should.raise(TypeError)
  end

  it "divides correctly by Rational numbers" do
    (1.2345678901234567 / Rational(1, 10000000000000000000)).should == 1.2345678901234567e+19
  end
end
