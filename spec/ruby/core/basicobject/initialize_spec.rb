require_relative '../../spec_helper'

describe "BasicObject#initialize" do
  it "is a private instance method" do
    BasicObject.private_instance_methods(false).should.include?(:initialize)
  end

  it "does not accept arguments" do
    -> {
      BasicObject.new("This", "makes it easier", "to call super", "from other constructors")
    }.should.raise(ArgumentError)
  end
end
