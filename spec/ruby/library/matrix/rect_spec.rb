require_relative '../../spec_helper'
require 'matrix'

describe "Matrix#rect" do
  it "is an alias of Matrix#rectangular" do
    Matrix.instance_method(:rect).should == Matrix.instance_method(:rectangular)
  end
end
