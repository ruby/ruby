# frozen_string_literal: true

module YARP
  class DesugarVisitor < MutationVisitor
    # @@foo &&= bar
    #
    # becomes
    #
    # @@foo && @@foo = bar
    def visit_class_variable_and_write_node(node)
      AndNode.new(
        ClassVariableReadNode.new(node.name_loc),
        ClassVariableWriteNode.new(node.name_loc, node.value, node.operator_loc, node.location),
        node.operator_loc,
        node.location
      )
    end

    # @@foo ||= bar
    #
    # becomes
    #
    # @@foo || @@foo = bar
    def visit_class_variable_or_write_node(node)
      OrNode.new(
        ClassVariableReadNode.new(node.name_loc),
        ClassVariableWriteNode.new(node.name_loc, node.value, node.operator_loc, node.location),
        node.operator_loc,
        node.location
      )
    end

    # @@foo += bar
    #
    # becomes
    #
    # @@foo = @@foo + bar
    def visit_class_variable_operator_write_node(node)
      desugar_operator_write_node(node, ClassVariableWriteNode, ClassVariableReadNode)
    end

    # Foo &&= bar
    #
    # becomes
    #
    # Foo && Foo = bar
    def visit_constant_and_write_node(node)
      AndNode.new(
        ConstantReadNode.new(node.name_loc),
        ConstantWriteNode.new(node.name_loc, node.value, node.operator_loc, node.location),
        node.operator_loc,
        node.location
      )
    end

    # Foo ||= bar
    #
    # becomes
    #
    # Foo || Foo = bar
    def visit_constant_or_write_node(node)
      OrNode.new(
        ConstantReadNode.new(node.name_loc),
        ConstantWriteNode.new(node.name_loc, node.value, node.operator_loc, node.location),
        node.operator_loc,
        node.location
      )
    end

    # Foo += bar
    #
    # becomes
    #
    # Foo = Foo + bar
    def visit_constant_operator_write_node(node)
      desugar_operator_write_node(node, ConstantWriteNode, ConstantReadNode)
    end

    # Foo::Bar &&= baz
    #
    # becomes
    #
    # Foo::Bar && Foo::Bar = baz
    def visit_constant_path_and_write_node(node)
      AndNode.new(
        node.target,
        ConstantPathWriteNode.new(node.target, node.value, node.operator_loc, node.location),
        node.operator_loc,
        node.location
      )
    end

    # Foo::Bar ||= baz
    #
    # becomes
    #
    # Foo::Bar || Foo::Bar = baz
    def visit_constant_path_or_write_node(node)
      OrNode.new(
        node.target,
        ConstantPathWriteNode.new(node.target, node.value, node.operator_loc, node.location),
        node.operator_loc,
        node.location
      )
    end

    # Foo::Bar += baz
    #
    # becomes
    #
    # Foo::Bar = Foo::Bar + baz
    def visit_constant_path_operator_write_node(node)
      ConstantPathWriteNode.new(
        node.target,
        CallNode.new(
          node.target,
          nil,
          node.operator_loc.copy(length: node.operator_loc.length - 1),
          nil,
          ArgumentsNode.new([node.value], node.value.location),
          nil,
          nil,
          0,
          node.operator_loc.slice.chomp("="),
          node.location
        ),
        node.operator_loc.copy(start_offset: node.operator_loc.end_offset - 1, length: 1),
        node.location
      )
    end

    # $foo &&= bar
    #
    # becomes
    #
    # $foo && $foo = bar
    def visit_global_variable_and_write_node(node)
      AndNode.new(
        GlobalVariableReadNode.new(node.name_loc),
        GlobalVariableWriteNode.new(node.name_loc, node.value, node.operator_loc, node.location),
        node.operator_loc,
        node.location
      )
    end

    # $foo ||= bar
    #
    # becomes
    #
    # $foo || $foo = bar
    def visit_global_variable_or_write_node(node)
      OrNode.new(
        GlobalVariableReadNode.new(node.name_loc),
        GlobalVariableWriteNode.new(node.name_loc, node.value, node.operator_loc, node.location),
        node.operator_loc,
        node.location
      )
    end

    # $foo += bar
    #
    # becomes
    #
    # $foo = $foo + bar
    def visit_global_variable_operator_write_node(node)
      desugar_operator_write_node(node, GlobalVariableWriteNode, GlobalVariableReadNode)
    end

    # @foo &&= bar
    #
    # becomes
    #
    # @foo && @foo = bar
    def visit_instance_variable_and_write_node(node)
      AndNode.new(
        InstanceVariableReadNode.new(node.name_loc),
        InstanceVariableWriteNode.new(node.name_loc, node.value, node.operator_loc, node.location),
        node.operator_loc,
        node.location
      )
    end

    # @foo ||= bar
    #
    # becomes
    #
    # @foo || @foo = bar
    def visit_instance_variable_or_write_node(node)
      OrNode.new(
        InstanceVariableReadNode.new(node.name_loc),
        InstanceVariableWriteNode.new(node.name_loc, node.value, node.operator_loc, node.location),
        node.operator_loc,
        node.location
      )
    end

    # @foo += bar
    #
    # becomes
    #
    # @foo = @foo + bar
    def visit_instance_variable_operator_write_node(node)
      desugar_operator_write_node(node, InstanceVariableWriteNode, InstanceVariableReadNode)
    end

    # foo &&= bar
    #
    # becomes
    #
    # foo && foo = bar
    def visit_local_variable_and_write_node(node)
      AndNode.new(
        LocalVariableReadNode.new(node.name, node.depth, node.name_loc),
        LocalVariableWriteNode.new(node.name, node.depth, node.name_loc, node.value, node.operator_loc, node.location),
        node.operator_loc,
        node.location
      )
    end

    # foo ||= bar
    #
    # becomes
    #
    # foo || foo = bar
    def visit_local_variable_or_write_node(node)
      OrNode.new(
        LocalVariableReadNode.new(node.name, node.depth, node.name_loc),
        LocalVariableWriteNode.new(node.name, node.depth, node.name_loc, node.value, node.operator_loc, node.location),
        node.operator_loc,
        node.location
      )
    end

    # foo += bar
    #
    # becomes
    #
    # foo = foo + bar
    def visit_local_variable_operator_write_node(node)
      desugar_operator_write_node(node, LocalVariableWriteNode, LocalVariableReadNode, arguments: [node.name, node.depth])
    end

    private

    # Desugar `x += y` to `x = x + y`
    def desugar_operator_write_node(node, write_class, read_class, arguments: [])
      write_class.new(
        *arguments,
        node.name_loc,
        CallNode.new(
          read_class.new(*arguments, node.name_loc),
          nil,
          node.operator_loc.copy(length: node.operator_loc.length - 1),
          nil,
          ArgumentsNode.new([node.value], node.value.location),
          nil,
          nil,
          0,
          node.operator_loc.slice.chomp("="),
          node.location
        ),
        node.operator_loc.copy(start_offset: node.operator_loc.end_offset - 1, length: 1),
        node.location
      )
    end
  end
end
