require_relative '../../spec_helper'

describe "Complex#quo" do
  it "is an alias of Complex#/" do
    Complex.instance_method(:quo).should == Complex.instance_method(:/)
  end
end
