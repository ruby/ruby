require_relative '../../shared/complex/multiply'

describe "Complex#*" do
  it_behaves_like :complex_multiply, :*
end
