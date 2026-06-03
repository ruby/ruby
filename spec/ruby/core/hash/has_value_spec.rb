require_relative '../../spec_helper'

describe "Hash#has_value?" do
  it "returns true if the value exists in the hash" do
    { a: :b }.has_value?(:a).should == false
    { 1 => 2 }.has_value?(2).should == true
    h = Hash.new(5)
    h.has_value?(5).should == false
    h = Hash.new { 5 }
    h.has_value?(5).should == false
  end

  it "uses == semantics for comparing values" do
    { 5 => 2.0 }.has_value?(2).should == true
  end
end
