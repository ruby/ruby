# -*- encoding: utf-8 -*-
require_relative '../../spec_helper'

describe "Symbol#casecmp with Symbol" do
  it "compares symbols without regard to case" do
    :abcdef.casecmp(:abcde).should == 1
    :aBcDeF.casecmp(:abcdef).should == 0
    :abcdef.casecmp(:abcdefg).should == -1
    :abcdef.casecmp(:ABCDEF).should == 0
  end

  it "doesn't consider non-ascii characters equal that aren't" do
    # -- Latin-1 --
    upper_a_tilde  = "\xC3".b.to_sym
    upper_a_umlaut = "\xC4".b.to_sym
    lower_a_tilde  = "\xE3".b.to_sym
    lower_a_umlaut = "\xE4".b.to_sym

    lower_a_tilde.casecmp(lower_a_umlaut).should_not == 0
    lower_a_umlaut.casecmp(lower_a_tilde).should_not == 0
    upper_a_tilde.casecmp(upper_a_umlaut).should_not == 0
    upper_a_umlaut.casecmp(upper_a_tilde).should_not == 0

    # -- UTF-8 --
    upper_a_tilde  = :"Ã"
    lower_a_tilde  = :"ã"
    upper_a_umlaut = :"Ä"
    lower_a_umlaut = :"ä"

    lower_a_tilde.casecmp(lower_a_umlaut).should_not == 0
    lower_a_umlaut.casecmp(lower_a_tilde).should_not == 0
    upper_a_tilde.casecmp(upper_a_umlaut).should_not == 0
    upper_a_umlaut.casecmp(upper_a_tilde).should_not == 0
  end

  it "doesn't do case mapping for non-ascii characters" do
    # -- Latin-1 --
    upper_a_tilde  = "\xC3".b.to_sym
    upper_a_umlaut = "\xC4".b.to_sym
    lower_a_tilde  = "\xE3".b.to_sym
    lower_a_umlaut = "\xE4".b.to_sym

    upper_a_tilde.casecmp(lower_a_tilde).should == -1
    upper_a_umlaut.casecmp(lower_a_umlaut).should == -1
    lower_a_tilde.casecmp(upper_a_tilde).should == 1
    lower_a_umlaut.casecmp(upper_a_umlaut).should == 1

    # -- UTF-8 --
    upper_a_tilde  = :"Ã"
    lower_a_tilde  = :"ã"
    upper_a_umlaut = :"Ä"
    lower_a_umlaut = :"ä"

    upper_a_tilde.casecmp(lower_a_tilde).should == -1
    upper_a_umlaut.casecmp(lower_a_umlaut).should == -1
    lower_a_tilde.casecmp(upper_a_tilde).should == 1
    lower_a_umlaut.casecmp(upper_a_umlaut).should == 1
  end

  it "returns 0 for empty strings in different encodings" do
    ''.to_sym.casecmp(''.encode("UTF-32LE").to_sym).should == 0
  end
end

describe "Symbol#casecmp" do
  it "returns nil if other is a String" do
    :abc.casecmp("abc").should be_nil
  end

  it "returns nil if other is an Integer" do
    :abc.casecmp(1).should be_nil
  end

  it "returns nil if other is an object" do
    obj = mock("string <=>")
    :abc.casecmp(obj).should be_nil
  end
end

describe 'Symbol#casecmp?' do
  it "compares symbols without regard to case" do
    :abcdef.casecmp?(:abcde).should == false
    :aBcDeF.casecmp?(:abcdef).should == true
    :abcdef.casecmp?(:abcdefg).should == false
    :abcdef.casecmp?(:ABCDEF).should == true
  end

  it "doesn't consider non-ascii characters equal that aren't" do
    # -- Latin-1 --
    upper_a_tilde  = "\xC3".b.to_sym
    upper_a_umlaut = "\xC4".b.to_sym
    lower_a_tilde  = "\xE3".b.to_sym
    lower_a_umlaut = "\xE4".b.to_sym

    lower_a_tilde.casecmp?(lower_a_umlaut).should_not == true
    lower_a_umlaut.casecmp?(lower_a_tilde).should_not == true
    upper_a_tilde.casecmp?(upper_a_umlaut).should_not == true
    upper_a_umlaut.casecmp?(upper_a_tilde).should_not == true

    # -- UTF-8 --
    upper_a_tilde  = :"Ã"
    lower_a_tilde  = :"ã"
    upper_a_umlaut = :"Ä"
    lower_a_umlaut = :"ä"

    lower_a_tilde.casecmp?(lower_a_umlaut).should_not == true
    lower_a_umlaut.casecmp?(lower_a_tilde).should_not == true
    upper_a_tilde.casecmp?(upper_a_umlaut).should_not == true
    upper_a_umlaut.casecmp?(upper_a_tilde).should_not == true
  end

  it "doesn't do case mapping for non-ascii and non-unicode characters" do
    # -- Latin-1 --
    upper_a_tilde  = "\xC3".b.to_sym
    upper_a_umlaut = "\xC4".b.to_sym
    lower_a_tilde  = "\xE3".b.to_sym
    lower_a_umlaut = "\xE4".b.to_sym

    upper_a_tilde.casecmp?(lower_a_tilde).should == false
    upper_a_umlaut.casecmp?(lower_a_umlaut).should == false
    lower_a_tilde.casecmp?(upper_a_tilde).should == false
    lower_a_umlaut.casecmp?(upper_a_umlaut).should == false
  end

  it 'does case mapping for unicode characters' do
    # -- UTF-8 --
    upper_a_tilde  = :"Ã"
    lower_a_tilde  = :"ã"
    upper_a_umlaut = :"Ä"
    lower_a_umlaut = :"ä"

    upper_a_tilde.casecmp?(lower_a_tilde).should == true
    upper_a_umlaut.casecmp?(lower_a_umlaut).should == true
    lower_a_tilde.casecmp?(upper_a_tilde).should == true
    lower_a_umlaut.casecmp?(upper_a_umlaut).should == true
  end

  it 'returns nil when comparing characters with different encodings' do
    # -- Latin-1 --
    upper_a_tilde = "\xC3".b.to_sym

    # -- UTF-8 --
    lower_a_tilde = :"ã"

    upper_a_tilde.casecmp?(lower_a_tilde).should == nil
    lower_a_tilde.casecmp?(upper_a_tilde).should == nil
  end

  it "returns true for empty symbols in different encodings" do
    ''.to_sym.should.casecmp?(''.encode("UTF-32LE").to_sym)
  end
end
