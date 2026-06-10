require_relative '../../spec_helper'

describe "IO#to_path" do
  it "is an alias of IO#path" do
    IO.instance_method(:to_path).should == IO.instance_method(:path)
  end
end
