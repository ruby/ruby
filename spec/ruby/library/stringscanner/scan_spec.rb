require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#scan" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "returns the matched string" do
    @s.scan(/\w+/).should == "This"
    @s.scan(/.../).should == " is"
    @s.scan(//).should == ""
    @s.scan(/\s+/).should == " "
  end

  it "treats ^ as matching from the beginning of the current position" do
    @s.scan(/\w+/).should == "This"
    @s.scan(/^\d/).should be_nil
    @s.scan(/^\s/).should == " "
  end

  it "treats ^ as matching from the beginning of the current position when it's not the first character in the regexp" do
    @s.scan(/\w+/).should == "This"
    @s.scan(/( is not|^ is a)/).should == " is a"
  end

  it "treats \\A as matching from the beginning of the current position" do
    @s.scan(/\w+/).should == "This"
    @s.scan(/\A\d/).should be_nil
    @s.scan(/\A\s/).should == " "
  end

  it "treats \\A as matching from the beginning of the current position when it's not the first character in the regexp" do
    @s.scan(/\w+/).should == "This"
    @s.scan(/( is not|\A is a)/).should == " is a"
  end

  it "returns nil if there's no match" do
    @s.scan(/\d/).should == nil
  end

  it "returns nil when there is no more to scan" do
    @s.scan(/[\w\s]+/).should == "This is a test"
    @s.scan(/\w+/).should be_nil
  end

  it "returns an empty string when the pattern matches empty" do
    @s.scan(/.*/).should == "This is a test"
    @s.scan(/.*/).should == ""
    @s.scan(/./).should be_nil
  end

  it "treats String as the pattern itself" do
    @s.scan("this").should be_nil
    @s.scan("This").should == "This"
  end

  it "raises a TypeError if pattern isn't a Regexp nor String" do
    -> { @s.scan(5)         }.should raise_error(TypeError)
    -> { @s.scan(:test)     }.should raise_error(TypeError)
    -> { @s.scan(mock('x')) }.should raise_error(TypeError)
  end
end

describe "StringScanner#scan with fixed_anchor: true" do
  before :each do
    @s = StringScanner.new("This\nis\na\ntest", fixed_anchor: true)
  end

  it "returns the matched string" do
    @s.scan(/\w+/).should == "This"
    @s.scan(/.../m).should == "\nis"
    @s.scan(//).should == ""
    @s.scan(/\s+/).should == "\n"
  end

  it "treats ^ as matching from the beginning of line" do
    @s.scan(/\w+\n/).should == "This\n"
    @s.scan(/^\w/).should == "i"
    @s.scan(/^\w/).should be_nil
  end

  it "treats \\A as matching from the beginning of string" do
    @s.scan(/\A\w/).should == "T"
    @s.scan(/\A\w/).should be_nil
  end
end
