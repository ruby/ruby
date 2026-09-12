require_relative '../../spec_helper'
require_relative '../../fixtures/source_range_helpers'
require_relative 'shared/syntax_tree'

ruby_version_is "4.1" do
  describe "Method#syntax_tree" do
    before :each do
      @object = -> method { method }

      skip "parse.y" unless syntax_tree_returns_prism_node
    end

    it_behaves_like :method_syntax_tree, :syntax_tree
  end
end
