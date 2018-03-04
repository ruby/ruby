require_relative '../../spec_helper'
require_relative 'shared/conjugate'

describe "Matrix#conj" do
  it_behaves_like :matrix_conjugate, :conj
end
