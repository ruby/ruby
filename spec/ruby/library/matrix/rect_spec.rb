require_relative '../../spec_helper'
require_relative 'shared/rectangular'

describe "Matrix#rect" do
  it_behaves_like :matrix_rectangular, :rect
end
