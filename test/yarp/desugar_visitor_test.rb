# frozen_string_literal: true

require_relative "test_helper"

module YARP
  class DesugarVisitorTest < TestCase
    def test_and_write
      assert_desugars("(AndNode (ClassVariableReadNode) (ClassVariableWriteNode (CallNode)))", "@@foo &&= bar")
      assert_not_desugared("Foo::Bar &&= baz", "Desugaring would execute Foo twice or need temporary variables")
      assert_desugars("(AndNode (ConstantReadNode) (ConstantWriteNode (CallNode)))", "Foo &&= bar")
      assert_desugars("(AndNode (GlobalVariableReadNode) (GlobalVariableWriteNode (CallNode)))", "$foo &&= bar")
      assert_desugars("(AndNode (InstanceVariableReadNode) (InstanceVariableWriteNode (CallNode)))", "@foo &&= bar")
      assert_desugars("(AndNode (LocalVariableReadNode) (LocalVariableWriteNode (CallNode)))", "foo &&= bar")
      assert_desugars("(AndNode (LocalVariableReadNode) (LocalVariableWriteNode (CallNode)))", "foo = 1; foo &&= bar")
    end

    def test_or_write
      assert_desugars("(IfNode (DefinedNode (ClassVariableReadNode)) (StatementsNode (ClassVariableReadNode)) (ElseNode (StatementsNode (ClassVariableWriteNode (CallNode)))))", "@@foo ||= bar")
      assert_not_desugared("Foo::Bar ||= baz", "Desugaring would execute Foo twice or need temporary variables")
      assert_desugars("(IfNode (DefinedNode (ConstantReadNode)) (StatementsNode (ConstantReadNode)) (ElseNode (StatementsNode (ConstantWriteNode (CallNode)))))", "Foo ||= bar")
      assert_desugars("(IfNode (DefinedNode (GlobalVariableReadNode)) (StatementsNode (GlobalVariableReadNode)) (ElseNode (StatementsNode (GlobalVariableWriteNode (CallNode)))))", "$foo ||= bar")
      assert_desugars("(OrNode (InstanceVariableReadNode) (InstanceVariableWriteNode (CallNode)))", "@foo ||= bar")
      assert_desugars("(OrNode (LocalVariableReadNode) (LocalVariableWriteNode (CallNode)))", "foo ||= bar")
      assert_desugars("(OrNode (LocalVariableReadNode) (LocalVariableWriteNode (CallNode)))", "foo = 1; foo ||= bar")
    end

    def test_operator_write
      assert_desugars("(ClassVariableWriteNode (CallNode (ClassVariableReadNode) (ArgumentsNode (CallNode))))", "@@foo += bar")
      assert_not_desugared("Foo::Bar += baz", "Desugaring would execute Foo twice or need temporary variables")
      assert_desugars("(ConstantWriteNode (CallNode (ConstantReadNode) (ArgumentsNode (CallNode))))", "Foo += bar")
      assert_desugars("(GlobalVariableWriteNode (CallNode (GlobalVariableReadNode) (ArgumentsNode (CallNode))))", "$foo += bar")
      assert_desugars("(InstanceVariableWriteNode (CallNode (InstanceVariableReadNode) (ArgumentsNode (CallNode))))", "@foo += bar")
      assert_desugars("(LocalVariableWriteNode (CallNode (LocalVariableReadNode) (ArgumentsNode (CallNode))))", "foo += bar")
      assert_desugars("(LocalVariableWriteNode (CallNode (LocalVariableReadNode) (ArgumentsNode (CallNode))))", "foo = 1; foo += bar")
    end

    private

    def ast_inspect(node)
      parts = [node.class.name.split("::").last]

      node.deconstruct_keys(nil).each do |_, value|
        case value
        when Node
          parts << ast_inspect(value)
        when Array
          parts.concat(value.map { |element| ast_inspect(element) })
        end
      end

      "(#{parts.join(" ")})"
    end

    def assert_desugars(expected, source)
      ast = YARP.parse(source).value.accept(DesugarVisitor.new)
      assert_equal expected, ast_inspect(ast.statements.body.last)
    end

    def assert_not_desugared(source, reason)
      ast = YARP.parse(source).value
      assert_equal_nodes(ast, ast.accept(YARP::DesugarVisitor.new))
    end
  end
end
