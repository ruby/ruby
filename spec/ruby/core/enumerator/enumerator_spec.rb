require_relative '../../spec_helper'

describe "Enumerator" do
  it "includes Enumerable" do
    Enumerator.include?(Enumerable).should == true
  end
end
