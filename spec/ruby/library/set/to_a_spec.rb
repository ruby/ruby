require_relative '../../spec_helper'
require 'set'

describe "Set#to_a" do
  it "returns an array containing elements of self" do
    Set[1, 2, 3].to_a.sort.should == [1, 2, 3]
  end
end
