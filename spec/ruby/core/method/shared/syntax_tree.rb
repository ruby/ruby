require_relative '../../../fixtures/source_range_helpers'

describe :method_syntax_tree, shared: true do
  it "returns a DefNode for a def method" do
    def def_method
    end
    def_method_line = __LINE__ - 2

    node = @object.call(method(:def_method)).syntax_tree
    node.start_line.should == def_method_line
    node.should.is_a?(Ruby::Prism::DefNode)
  end

  it "returns a BlockNode for a define_method method" do
    define_singleton_method :define_method_method do
    end
    define_method_method_line = __LINE__ - 2

    node = @object.call(method(:define_method_method)).syntax_tree
    node.start_line.should == define_method_method_line
    node.should.is_a?(Ruby::Prism::BlockNode)
    node.slice.should == "do\n    end"
  end

  it "returns a BlockNode for a define_method(name, &proc) method" do
    def return_block(&b)
      b
    end
    body = return_block { 42 }
    define_singleton_method(:define_method_method_proc, &body)
    define_method_method_proc_line = __LINE__ - 2

    node = @object.call(method(:define_method_method_proc)).syntax_tree
    node.start_line.should == define_method_method_proc_line
    node.should.is_a?(Ruby::Prism::BlockNode)
    node.slice.should == "{ 42 }"
  end

  it "returns a node at the same location as #source_range" do
    obj = Object.new
    def obj.def_method(x, y)
      x + y
    end
    def obj.def_endless_method = 42
    obj.singleton_class.define_method :define_method_method do |x, y|
      x + y
    end
    obj.singleton_class.define_method(:define_method_method_inline) { |x, y| x + y }
    def obj.return_block(&b)
      b
    end
    obj.singleton_class.define_method(:define_method_method_proc, &obj.return_block { 42 })

    [
      :def_method,
      :def_endless_method,
      :define_method_method,
      :define_method_method_inline,
      :define_method_method_proc,
    ].each do |name|
      meth = @object.call(obj.method(name))
      source_range_values(meth.syntax_tree).should == source_range_values(meth.source_range)
    end
  end
end
