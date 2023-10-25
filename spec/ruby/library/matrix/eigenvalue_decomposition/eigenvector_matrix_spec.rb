require_relative '../../../spec_helper'

ruby_version_is ""..."3.1" do
  require 'matrix'

  describe "Matrix::EigenvalueDecomposition#eigenvector_matrix" do
    it "returns a complex eigenvector matrix given a rotation matrix" do
      # Fix me: should test for linearity, not for equality
      Matrix[[ 1, 1],
             [-1, 1]].eigensystem.eigenvector_matrix.should ==
      Matrix[[1, 1],
             [Complex(0, 1), Complex(0, -1)]]
    end

    it "returns an real eigenvector matrix for a symmetric matrix" do
      # Fix me: should test for linearity, not for equality
      Matrix[[1, 2],
             [2, 1]].eigensystem.eigenvector_matrix.should ==
      Matrix[[0.7071067811865475, 0.7071067811865475],
             [-0.7071067811865475, 0.7071067811865475]]
    end
  end
end
