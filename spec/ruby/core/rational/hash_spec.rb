require_relative '../../shared/rational/hash'

describe "Rational#hash" do
  it_behaves_like :rational_hash, :hash
end
