require_relative '../../spec_helper'

describe "IO" do
  it "includes File::Constants" do
    IO.include?(File::Constants).should == true
  end

  it "includes Enumerable" do
    IO.include?(Enumerable).should == true
  end
end
