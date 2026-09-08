require_relative '../../../../spec_helper'

ruby_version_is "4.1" do
  describe "Thread::Backtrace::Location#syntax_tree" do
    # This is tested more extensively in core/thread/backtrace/location/source_range_spec.rb

    before do
      skip "parse.y" if proc {}.syntax_tree.is_a?(RubyVM::AbstractSyntaxTree::Node)
    end

    it "returns a CallNode for the first location from caller_locations" do
      node = -> { caller_locations(0, 1)[0] }.call.syntax_tree
      node.start_line.should == __LINE__ - 1
      node.should.is_a?(Prism::CallNode)
      node.name.should == :caller_locations
    end
  end
end
