require_relative '../../shared/enumerator/each'

describe "Enumerator#each" do
  it_behaves_like :enum_each, :each
end
