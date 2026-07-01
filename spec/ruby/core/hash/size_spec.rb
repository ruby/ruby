require_relative '../../spec_helper'

describe "Hash#size" do
  it "returns the number of entries" do
    { a: 1, b: 'c' }.size.should == 2
    h = { a: 1, b: 2 }
    h[:a] = 2
    h.size.should == 2
    { a: 1, b: 1, c: 1 }.size.should == 3
    {}.size.should == 0
    Hash.new(5).size.should == 0
    Hash.new { 5 }.size.should == 0
  end
end
