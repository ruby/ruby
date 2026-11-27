require_relative '../../spec_helper'
require 'matrix'

describe "Matrix.I" do
  it "is an alias of Matrix.identity" do
    Matrix.method(:I).should == Matrix.method(:identity)
  end
end
