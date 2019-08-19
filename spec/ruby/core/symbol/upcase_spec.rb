# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'

describe "Symbol#upcase" do
  it "returns a Symbol" do
    :glark.upcase.should be_an_instance_of(Symbol)
  end

  it "converts lowercase ASCII characters to their uppercase equivalents" do
    :lOwEr.upcase.should == :LOWER
  end

  ruby_version_is ''...'2.4' do
    it "leaves lowercase Unicode characters as they were" do
      "\u{E0}Bc".to_sym.upcase.should == :"àBC"
    end
  end

  ruby_version_is '2.4' do
    it "capitalizes all Unicode characters" do
      "äöü".to_sym.upcase.should == :"ÄÖÜ"
      "aou".to_sym.upcase.should == :"AOU"
    end
  end

  it "leaves non-alphabetic ASCII characters as they were" do
    "Glark?!?".to_sym.upcase.should == :"GLARK?!?"
  end
end
