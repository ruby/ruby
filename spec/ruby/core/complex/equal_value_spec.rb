require_relative '../../shared/complex/equal_value'

describe "Complex#==" do
  it_behaves_like :complex_equal_value, :==
end
