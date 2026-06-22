require_relative '../../spec_helper'

describe "Proc#[]" do
  it "is an alias of Proc#call" do
    Proc.instance_method(:[]).should == Proc.instance_method(:call)
  end
end
