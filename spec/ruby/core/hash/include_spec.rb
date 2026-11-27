require_relative '../../spec_helper'

describe "Hash#include?" do
  it "returns true if argument is a key" do
    h = { a: 1, b: 2, c: 3, 4 => 0 }
    h.include?(:a).should == true
    h.include?(:b).should == true
    h.include?(2).should == false
    h.include?(4).should == true

    not_supported_on :opal do
      h.include?('b').should == false
      h.include?(4.0).should == false
    end
  end

  it "returns true if the key's matching value was nil" do
    { xyz: nil }.include?(:xyz).should == true
  end

  it "returns true if the key's matching value was false" do
    { xyz: false }.include?(:xyz).should == true
  end

  it "returns true if the key is nil" do
    { nil => 'b' }.include?(nil).should == true
    { nil => nil }.include?(nil).should == true
  end

  it "compares keys with the same #hash value via #eql?" do
    x = mock('x')
    x.stub!(:hash).and_return(42)

    y = mock('y')
    y.stub!(:hash).and_return(42)
    y.should_receive(:eql?).and_return(false)

    { x => nil }.include?(y).should == false
  end
end
