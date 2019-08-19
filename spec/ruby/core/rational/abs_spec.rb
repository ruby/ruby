require_relative '../../shared/rational/abs'

describe "Rational#abs" do
  it_behaves_like :rational_abs, :abs
end
