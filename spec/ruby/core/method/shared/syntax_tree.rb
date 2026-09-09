require_relative '../../../fixtures/source_range_helpers'

describe :method_syntax_tree, shared: true do
  it "returns a DefNode for a def method" do
    def def_method
    end
    def_method_line = __LINE__ - 2

    node = @object.call(method(:def_method)).syntax_tree
    node.start_line.should == def_method_line
    node.should.is_a?(Prism::DefNode)
  end

  it "currently returns a CallNode for a define_method method" do
    define_singleton_method :define_method_method do
    end
    define_method_method_line = __LINE__ - 2

    node = @object.call(method(:define_method_method)).syntax_tree
    node.start_line.should == define_method_method_line
    node.should.is_a?(Prism::CallNode)
  end

  it "currently returns a CallNode for a define_method(name, &proc) method" do
    def return_block(&b)
      b
    end
    body = return_block { 42 }
    define_singleton_method(:define_method_method_proc, &body)
    define_method_method_proc_line = __LINE__ - 2

    node = @object.call(method(:define_method_method_proc)).syntax_tree
    node.start_line.should == define_method_method_proc_line
    node.should.is_a?(Prism::CallNode)
  end
end
