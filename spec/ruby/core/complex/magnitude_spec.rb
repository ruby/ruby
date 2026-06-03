require_relative '../../spec_helper'

describe "Complex#magnitude" do
  it "is an alias of Complex#abs" do
    Complex.instance_method(:magnitude).should == Complex.instance_method(:abs)
  end
end
