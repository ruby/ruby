require_relative '../../spec_helper'
require_relative 'shared/codepoints'
require_relative 'shared/each_codepoint_without_block'

with_feature :encoding do
  describe "String#each_codepoint" do
    it_behaves_like :string_codepoints, :each_codepoint
    it_behaves_like :string_each_codepoint_without_block, :each_codepoint
  end
end
