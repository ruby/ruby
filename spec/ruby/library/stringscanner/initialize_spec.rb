require_relative '../../spec_helper'
require 'strscan'

describe "StringScanner#initialize" do
  before :each do
    @s = StringScanner.new("This is a test")
  end

  it "is a private method" do
    StringScanner.private_instance_methods(false).should.include?(:initialize)
  end

  it "returns an instance of StringScanner" do
    @s.should.is_a?(StringScanner)
    @s.eos?.should == false
  end

  it "converts the argument into a string using #to_str" do
    m = mock(:str)

    s = "test"
    m.should_receive(:to_str).and_return(s)

    scan = StringScanner.new(m)
    scan.string.should == s
  end

  it "accepts a fixed_anchor keyword argument" do
    s = StringScanner.new("foo", fixed_anchor: true)
    s.should.fixed_anchor?
  end
end
