require_relative '../../spec_helper'
require_relative 'fixtures/classes'

describe "Hash#empty?" do
  it "returns true if the hash has no entries" do
    {}.empty?.should == true
    { 1 => 1 }.empty?.should == false
  end

  it "returns true if the hash has no entries and has a default value" do
    Hash.new(5).empty?.should == true
    Hash.new { 5 }.empty?.should == true
    Hash.new { |hsh, k| hsh[k] = k }.empty?.should == true
  end
end
