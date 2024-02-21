require_relative '../../spec_helper'
require_relative 'shared/conjugate'

describe "Matrix#conjugate" do
  it_behaves_like :matrix_conjugate, :conjugate
end
