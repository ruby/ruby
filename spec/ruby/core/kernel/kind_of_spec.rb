require_relative '../../spec_helper'

describe "Kernel#kind_of?" do
  it "is an alias of Kernel#is_a?" do
    Kernel.instance_method(:kind_of?).should == Kernel.instance_method(:is_a?)
  end
end
