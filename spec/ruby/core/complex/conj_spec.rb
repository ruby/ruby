require_relative '../../spec_helper'
require_relative '../../shared/complex/conjugate'

describe "Complex#conj" do
  it_behaves_like :complex_conjugate, :conj
end
