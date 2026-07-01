require_relative '../../spec_helper'
require 'matrix'

describe "Matrix.new" do
  it "is private" do
    Matrix.private_methods(false).should.include?(:new)
  end
end
