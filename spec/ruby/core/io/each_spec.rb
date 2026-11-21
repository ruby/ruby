require_relative '../../spec_helper'

describe "IO#each" do
  it "is an alias of IO#each_line" do
    IO.instance_method(:each).should == IO.instance_method(:each_line)
  end
end
