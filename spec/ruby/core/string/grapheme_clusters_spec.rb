require_relative "../../spec_helper"
require_relative 'shared/chars'
require_relative 'shared/grapheme_clusters'

describe "String#grapheme_clusters" do
  it_behaves_like :string_chars, :grapheme_clusters
  it_behaves_like :string_grapheme_clusters, :grapheme_clusters

  it "returns an array when no block given" do
    string = "ab\u{1f3f3}\u{fe0f}\u{200d}\u{1f308}\u{1F43E}"
    string.grapheme_clusters.should == ['a', 'b', "\u{1f3f3}\u{fe0f}\u{200d}\u{1f308}", "\u{1F43E}"]

  end
end
