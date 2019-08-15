require_relative '../../spec_helper'
require_relative 'shared/identity'

describe "Matrix.identity" do
  it_behaves_like :matrix_identity, :identity
end
