require_relative '../../spec_helper'
require_relative '../../fixtures/source_range_helpers'

ruby_version_is "4.1" do
  describe "Proc#syntax_tree" do
    before :each do
      skip "parse.y" unless syntax_tree_returns_prism_node
    end

    def return_block(&b)
      b
    end

    it "currently returns a CallNode and not a BlockNode for a block" do
      node = proc { 42 }.syntax_tree
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Prism::CallNode)

      node = lambda { 42 }.syntax_tree # rubocop:disable Style/Lambda
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Prism::CallNode)

      node = return_block { 42 }.syntax_tree
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Prism::CallNode)
    end

    it "currently returns a CallNode and not a BlockNode for a block with rescue" do
      # Interesting because the BlockNode and the BeginNode are fully overlapping
      node = proc do; rescue; end.syntax_tree
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Prism::CallNode)
    end

    it "returns a LambdaNode for a stabby lambda" do
      node = -> { 42 }.syntax_tree
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Prism::LambdaNode)
    end

    it "does not return implicit parameter nodes" do
      # Interesting because the BlockNode and the ItParametersNode/NumberedParametersNode are fully overlapping
      node = -> { it }.syntax_tree
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Prism::LambdaNode)

      node = -> { _1 }.syntax_tree
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Prism::LambdaNode)

      node = proc { it }.syntax_tree
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Prism::CallNode)

      node = proc { _1 }.syntax_tree
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Prism::CallNode)
    end

    it "returns a ForNode for a for-loop block" do
      iter = Object.new
      def iter.each(&block)
        block.call(block)
      end
      for b in iter
        node = b.syntax_tree
      end

      node.start_line.should == __LINE__ - 4
      node.should.is_a?(Prism::ForNode)
    end
  end
end
