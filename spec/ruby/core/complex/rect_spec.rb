require_relative '../../spec_helper'

describe "Complex#rect" do
  it "is an alias of Complex#rectangular" do
    Complex.instance_method(:rect).should == Complex.instance_method(:rectangular)
  end
end

describe "Complex.rect" do
  it "is an alias of Complex#rectangular" do
    Complex.method(:rect).should == Complex.method(:rectangular)
  end
end
