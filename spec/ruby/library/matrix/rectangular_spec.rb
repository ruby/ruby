require_relative '../../spec_helper'
require_relative 'shared/rectangular'

describe "Matrix#rectangular" do
  it_behaves_like :matrix_rectangular, :rectangular
end
