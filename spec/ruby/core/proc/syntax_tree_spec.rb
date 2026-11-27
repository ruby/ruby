require_relative '../../spec_helper'
require_relative '../../fixtures/source_range_helpers'

ruby_version_is "4.1" do
  describe "Proc#syntax_tree" do
    before :each do
      skip "parse.y" unless syntax_tree_returns_prism_node
    end

    def return_block(*, &b)
      b
    end

    it "returns a BlockNode and not the CallNode for a block" do
      node = proc { 42 }.syntax_tree
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Ruby::Prism::BlockNode)
      node.slice.should == "{ 42 }"

      node = lambda { 42 }.syntax_tree # rubocop:disable Style/Lambda
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Ruby::Prism::BlockNode)
      node.slice.should == "{ 42 }"

      node = return_block(1 + 2) { 42 }.syntax_tree
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Ruby::Prism::BlockNode)
      node.slice.should == "{ 42 }"
    end

    it "returns a BlockNode for a block with rescue" do
      # Interesting because the BlockNode and the BeginNode are fully overlapping
      node = proc do; rescue; end.syntax_tree
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Ruby::Prism::BlockNode)
    end

    it "returns a node at the same location as #source_range" do
      obj = Object.new
      def obj.return_block(*, &b)
        b
      end
      iter = Object.new
      def iter.each(&block)
        block.call(block)
      end
      for for_proc in iter
        42
      end

      [
        proc { 42 },
        Proc.new { 42 },
        lambda { 42 }, # rubocop:disable Style/Lambda
        -> { 42 },
        ->(x, y) do x + y end,
        return_block(1 + 2) do
          42
        end,
        return_block { |x,
                        y| x + y },
        obj.return_block(1 + 2) { 42 },
        obj.return_block { <<~END },
          heredoc
        END
        for_proc,
      ].each do |pr|
        source_range_values(pr.syntax_tree).should == source_range_values(pr.source_range)
      end
    end

    it "returns the DefNode of the method for a proc created with Method#to_proc" do
      obj = Object.new
      def obj.def_method(x, y)
        x + y
      end
      def_method_line = __LINE__ - 3
      pr = obj.method(:def_method).to_proc

      node = pr.syntax_tree
      node.start_line.should == def_method_line
      node.should.is_a?(Ruby::Prism::DefNode)
      source_range_values(node).should == source_range_values(pr.source_range)
    end

    it "returns nil for a proc created with Method#to_proc of a method not written in Ruby" do
      [].method(:<<).to_proc.syntax_tree.should == nil
    end

    it "returns a LambdaNode for a stabby lambda" do
      node = -> { 42 }.syntax_tree
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Ruby::Prism::LambdaNode)
    end

    quarantine! do # NoMethodError: undefined method 'start_line' for nil
    it "does not return implicit parameter nodes" do
      # Interesting because the BlockNode and the ItParametersNode/NumberedParametersNode are fully overlapping
      node = eval('-> { it }.syntax_tree') # emits a warning on Ruby 3.3
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Ruby::Prism::LambdaNode)

      node = -> { _1 }.syntax_tree
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Ruby::Prism::LambdaNode)

      node = eval('proc { it }.syntax_tree') # emits a warning on Ruby 3.3
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Ruby::Prism::BlockNode)

      node = proc { _1 }.syntax_tree
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Ruby::Prism::BlockNode)
    end
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
      node.should.is_a?(Ruby::Prism::ForNode)
    end
  end
end
