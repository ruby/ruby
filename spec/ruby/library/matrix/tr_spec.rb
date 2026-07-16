require_relative '../../spec_helper'
require 'matrix'

describe "Matrix#tr" do
  it "is an alias of Matrix#trace" do
    Matrix.instance_method(:tr).should == Matrix.instance_method(:trace)
  end
end
