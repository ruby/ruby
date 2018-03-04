require_relative '../../shared/complex/abs'

describe "Complex#abs" do
  it_behaves_like :complex_abs, :abs
end
