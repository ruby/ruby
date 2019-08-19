require_relative '../../shared/rational/truncate'

describe "Rational#truncate" do
  it_behaves_like :rational_truncate, :truncate
end
