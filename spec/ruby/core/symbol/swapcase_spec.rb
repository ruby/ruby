# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'

describe "Symbol#swapcase" do
  it "returns a Symbol" do
    :glark.swapcase.should be_an_instance_of(Symbol)
  end

  it "converts lowercase ASCII characters to their uppercase equivalents" do
    :lower.swapcase.should == :LOWER
  end

  it "converts uppercase ASCII characters to their lowercase equivalents" do
    :UPPER.swapcase.should == :upper
  end

  it "works with both upper- and lowercase ASCII characters in the same Symbol" do
    :mIxEd.swapcase.should == :MiXeD
  end

  it "swaps the case for Unicode characters" do
    "äÖü".to_sym.swapcase.should == :"ÄöÜ"
    "aOu".to_sym.swapcase.should == :"AoU"
  end

  it "leaves non-alphabetic ASCII characters as they were" do
    "Glark?!?".to_sym.swapcase.should == :"gLARK?!?"
  end
end
