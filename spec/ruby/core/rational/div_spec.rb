require_relative "../../spec_helper"

describe "Rational#div" do
  it "returns an Integer" do
    Rational(229, 21).div(82).should.is_a?(Integer)
  end

  it "raises an ArgumentError if passed more than one argument" do
    -> { Rational(3, 4).div(2,3) }.should.raise(ArgumentError)
  end

  # See http://redmine.ruby-lang.org/issues/show/1648
  it "raises a TypeError if passed a non-numeric argument" do
    -> { Rational(3, 4).div([]) }.should.raise(TypeError)
  end
end

describe "Rational#div passed a Rational" do
  it "performs integer division and returns the result" do
    Rational(2, 3).div(Rational(2, 3)).should == 1
    Rational(-2, 9).div(Rational(-9, 2)).should == 0
  end

  it "raises a ZeroDivisionError when the argument has a numerator of 0" do
    -> { Rational(3, 4).div(Rational(0, 3)) }.should.raise(ZeroDivisionError)
  end

  it "raises a ZeroDivisionError when the argument has a numerator of 0.0" do
    -> { Rational(3, 4).div(Rational(0.0, 3)) }.should.raise(ZeroDivisionError)
  end
end

describe "Rational#div passed an Integer" do
  it "performs integer division and returns the result" do
    Rational(2, 1).div(1).should == 2
    Rational(25, 5).div(-50).should == -1
  end

  it "raises a ZeroDivisionError when the argument is 0" do
    -> { Rational(3, 4).div(0) }.should.raise(ZeroDivisionError)
  end
end

describe "Rational#div passed a Float" do
  it "performs integer division and returns the result" do
    Rational(2, 3).div(30.333).should == 0
    Rational(2, 9).div(Rational(-8.6)).should == -1
    Rational(3.12).div(0.5).should == 6
  end

  it "raises a ZeroDivisionError when the argument is 0.0" do
    -> { Rational(3, 4).div(0.0) }.should.raise(ZeroDivisionError)
  end
end
