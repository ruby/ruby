require_relative '../../spec_helper'

describe "Hash#value?" do
  it "returns true if the value exists in the hash" do
    { a: :b }.value?(:a).should == false
    { 1 => 2 }.value?(2).should == true
    h = Hash.new(5)
    h.value?(5).should == false
    h = Hash.new { 5 }
    h.value?(5).should == false
  end

  it "uses == semantics for comparing values" do
    { 5 => 2.0 }.value?(2).should == true
  end
end
