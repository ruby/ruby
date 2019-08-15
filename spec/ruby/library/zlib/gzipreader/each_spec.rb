require_relative 'shared/each'

describe "GzipReader#each" do
  it_behaves_like :gzipreader_each, :each
end
