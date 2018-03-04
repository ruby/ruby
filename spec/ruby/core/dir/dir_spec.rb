require_relative '../../spec_helper'

describe "Dir" do
  it "includes Enumerable" do
    Dir.include?(Enumerable).should == true
  end
end
