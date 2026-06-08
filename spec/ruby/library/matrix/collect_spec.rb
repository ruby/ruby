require_relative '../../spec_helper'
require 'matrix'

describe "Matrix#collect" do
  it "is an alias of Matrix#map" do
    Matrix.instance_method(:collect).should == Matrix.instance_method(:map)
  end
end
