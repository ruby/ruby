require_relative '../../spec_helper'
require_relative 'shared/conjugate'

describe "Complex#conjugate" do
  it_behaves_like :complex_conjugate, :conjugate
end
