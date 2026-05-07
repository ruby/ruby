require_relative '../../spec_helper'

describe "Rational#marshal_dump" do
  it "is a private method" do
    Rational.private_instance_methods(false).should.include?(:marshal_dump)
  end

  it "dumps numerator and denominator" do
    Rational(1, 2).send(:marshal_dump).should == [1, 2]
  end
end
