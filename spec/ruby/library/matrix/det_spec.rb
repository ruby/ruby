require_relative '../../spec_helper'
require_relative 'shared/determinant'
require 'matrix'

describe "Matrix#det" do
  it_behaves_like :determinant, :det
end
