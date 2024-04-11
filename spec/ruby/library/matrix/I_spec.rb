require_relative '../../spec_helper'
require_relative 'shared/identity'

describe "Matrix.I" do
  it_behaves_like :matrix_identity, :I
end
