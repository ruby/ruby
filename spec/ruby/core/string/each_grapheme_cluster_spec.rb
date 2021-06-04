require_relative 'shared/chars'
require_relative 'shared/grapheme_clusters'
require_relative 'shared/each_char_without_block'

describe "String#each_grapheme_cluster" do
  it_behaves_like :string_chars, :each_grapheme_cluster
  it_behaves_like :string_grapheme_clusters, :each_grapheme_cluster
  it_behaves_like :string_each_char_without_block, :each_grapheme_cluster
end
