require_relative '../../spec_helper'
require_relative 'shared/determinant'
require 'matrix'

describe "Matrix#determinant" do
  it_behaves_like :determinant, :determinant
end
