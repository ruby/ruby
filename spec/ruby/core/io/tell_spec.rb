require_relative '../../spec_helper'

describe "IO#tell" do
  it "is an alias of IO#pos" do
    IO.instance_method(:tell).should == IO.instance_method(:pos)
  end
end
