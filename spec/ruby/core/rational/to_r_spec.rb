require_relative "../../spec_helper"

describe "Rational#to_r" do
  it "returns self" do
    a = Rational(3, 4)
    a.to_r.should equal(a)

    a = Rational(bignum_value, 4)
    a.to_r.should equal(a)
  end

  it "raises TypeError trying to convert BasicObject" do
    obj = BasicObject.new
    -> { Rational(obj) }.should raise_error(TypeError)
  end

  it "works when a BasicObject has to_r" do
    obj = BasicObject.new; def obj.to_r; 1 / 2.to_r end
    Rational(obj).should == Rational('1/2')
  end

  it "fails when a BasicObject's to_r does not return a Rational" do
    obj = BasicObject.new; def obj.to_r; 1 end
    -> { Rational(obj) }.should raise_error(TypeError)
  end
end
