# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'

describe "Symbol#downcase" do
  it "returns a Symbol" do
    :glark.downcase.should be_an_instance_of(Symbol)
  end

  it "converts uppercase ASCII characters to their lowercase equivalents" do
    :lOwEr.downcase.should == :lower
  end

  it "leaves lowercase Unicode characters as they were" do
    "\u{E0}Bc".to_sym.downcase.should == :"àbc"
  end

  ruby_version_is ''...'2.4' do
    it "leaves uppercase Unicode characters as they were" do
      "\u{DE}Bc".to_sym.downcase.should == :"Þbc"
    end
  end

  ruby_version_is '2.4' do
    it "uncapitalizes all Unicode characters" do
      "ÄÖÜ".to_sym.downcase.should == :"äöü"
      "AOU".to_sym.downcase.should == :"aou"
    end
  end

  it "leaves non-alphabetic ASCII characters as they were" do
    "Glark?!?".to_sym.downcase.should == :"glark?!?"
  end
end
