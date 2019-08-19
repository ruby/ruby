require_relative '../../spec_helper'

describe "ArgumentError" do
  it "is a subclass of StandardError" do
    StandardError.should be_ancestor_of(ArgumentError)
  end

  it "gives its own class name as message if it has no message" do
    ArgumentError.new.message.should == "ArgumentError"
  end
end
