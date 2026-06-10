require_relative '../../spec_helper'

describe "IO#to_i" do
  it "is an alias of IO#fileno" do
    IO.instance_method(:to_i).should == IO.instance_method(:fileno)
  end
end
