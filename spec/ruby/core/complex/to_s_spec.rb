require_relative '../../shared/complex/to_s'

describe "Complex#to_s" do
  it_behaves_like :complex_to_s, :to_s
end
