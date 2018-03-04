require_relative '../../shared/complex/divide'

describe "Complex#quo" do
  it_behaves_like :complex_divide, :quo
end
