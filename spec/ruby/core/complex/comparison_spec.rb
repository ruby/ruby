require_relative '../../spec_helper'

describe "Complex#<=>" do
  it "returns nil if either self or argument has imaginary part" do
    (Complex(5, 1) <=> Complex(2)).should be_nil
    (Complex(1) <=> Complex(2, 1)).should be_nil
    (5 <=> Complex(2, 1)).should be_nil
  end

  it "returns nil if argument is not numeric" do
    (Complex(5, 1) <=> "cmp").should be_nil
    (Complex(1) <=> "cmp").should be_nil
    (Complex(1) <=> Object.new).should be_nil
  end

  it "returns 0, 1, or -1 if self and argument do not have imaginary part" do
    (Complex(5) <=> Complex(2)).should == 1
    (Complex(2) <=> Complex(3)).should == -1
    (Complex(2) <=> Complex(2)).should == 0

    (Complex(5) <=> 2).should == 1
    (Complex(2) <=> 3).should == -1
    (Complex(2) <=> 2).should == 0
  end
end
