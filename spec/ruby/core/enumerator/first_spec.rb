require_relative '../../spec_helper'

describe "Enumerator#first" do
  it "returns arrays correctly when calling #first (2376)" do
    Enumerator.new {|y| y << [42] }.first.should == [42]
  end
end
