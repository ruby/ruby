# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'

describe "Symbol#upcase" do
  it "returns a Symbol" do
    :glark.upcase.should be_an_instance_of(Symbol)
  end

  it "converts lowercase ASCII characters to their uppercase equivalents" do
    :lOwEr.upcase.should == :LOWER
  end

  it "capitalizes all Unicode characters" do
    "äöü".to_sym.upcase.should == :"ÄÖÜ"
    "aou".to_sym.upcase.should == :"AOU"
  end

  it "leaves non-alphabetic ASCII characters as they were" do
    "Glark?!?".to_sym.upcase.should == :"GLARK?!?"
  end
end
