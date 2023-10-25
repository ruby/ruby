require_relative '../../../spec_helper'

ruby_version_is ""..."3.1" do
  require 'matrix'

  describe "Matrix::LUPDecomposition#initialize" do
    it "raises an error if argument is not a matrix" do
      -> {
        Matrix::LUPDecomposition.new([[]])
      }.should raise_error(TypeError)
      -> {
        Matrix::LUPDecomposition.new(42)
      }.should raise_error(TypeError)
    end
  end
end
