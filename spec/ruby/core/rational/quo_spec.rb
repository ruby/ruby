require_relative "../../spec_helper"

describe "Rational#quo" do
  it "is an alias of Rational#/" do
    Rational.instance_method(:quo).should == Rational.instance_method(:/)
  end
end
