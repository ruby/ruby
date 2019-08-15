require_relative '../../spec_helper'
require 'matrix'

describe "Matrix.new" do
  it "is private" do
    Matrix.should have_private_method(:new)
  end
end
