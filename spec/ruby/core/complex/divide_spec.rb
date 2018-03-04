require_relative '../../shared/complex/divide'

describe "Complex#/" do
  it_behaves_like :complex_divide, :/
end
