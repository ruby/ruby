require_relative '../../spec_helper'

describe "BasicObject#initialize" do
  it "is a private instance method" do
    BasicObject.should have_private_instance_method(:initialize)
  end

  it "does not accept arguments" do
    lambda {
      BasicObject.new("This", "makes it easier", "to call super", "from other constructors")
    }.should raise_error(ArgumentError)
  end
end
