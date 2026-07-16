require_relative "../../spec_helper"

describe "Rational#magnitude" do
  it "is an alias of Rational#abs" do
    Rational.instance_method(:magnitude).should == Rational.instance_method(:abs)
  end
end
