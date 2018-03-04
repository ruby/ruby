require_relative '../../spec_helper'
require_relative 'shared/transpose'

describe "Matrix#transpose" do
  it_behaves_like :matrix_transpose, :transpose
end
