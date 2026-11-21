require_relative '../../spec_helper'

describe "IO#isatty" do
  it "is an alias of IO#tty?" do
    IO.instance_method(:isatty).should == IO.instance_method(:tty?)
  end
end
