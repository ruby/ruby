require_relative '../../shared/rational/modulo'

describe "Rational#%" do
  it_behaves_like :rational_modulo, :%
end
