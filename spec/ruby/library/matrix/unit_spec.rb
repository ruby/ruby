require_relative '../../spec_helper'
require_relative 'shared/identity'

describe "Matrix.unit" do
  it_behaves_like :matrix_identity, :unit
end
