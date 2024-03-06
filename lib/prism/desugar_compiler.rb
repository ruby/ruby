# frozen_string_literal: true

module Prism
  class DesugarAndWriteNode # :nodoc:
    attr_reader :node, :source, :read_class, :write_class, :arguments

    def initialize(node, source, read_class, write_class, *arguments)
      @node = node
      @source = source
      @read_class = read_class
      @write_class = write_class
      @arguments = arguments
    end

    # Desugar `x &&= y` to `x && x = y`
    def compile
      AndNode.new(
        source,
        read_class.new(source, *arguments, node.name_loc),
        write_class.new(source, *arguments, node.name_loc, node.value, node.operator_loc, node.location),
        node.operator_loc,
        node.location
      )
    end
  end

  class DesugarOrWriteDefinedNode # :nodoc:
    attr_reader :node, :source, :read_class, :write_class, :arguments

    def initialize(node, source, read_class, write_class, *arguments)
      @node = node
      @source = source
      @read_class = read_class
      @write_class = write_class
      @arguments = arguments
    end

    # Desugar `x ||= y` to `defined?(x) ? x : x = y`
    def compile
      IfNode.new(
        source,
        node.operator_loc,
        DefinedNode.new(source, nil, read_class.new(source, *arguments, node.name_loc), nil, node.operator_loc, node.name_loc),
        node.operator_loc,
        StatementsNode.new(source, [read_class.new(source, *arguments, node.name_loc)], node.location),
        ElseNode.new(
          source,
          node.operator_loc,
          StatementsNode.new(
            source,
            [write_class.new(source, *arguments, node.name_loc, node.value, node.operator_loc, node.location)],
            node.location
          ),
          node.operator_loc,
          node.location
        ),
        node.operator_loc,
        node.location
      )
    end
  end

  class DesugarOperatorWriteNode # :nodoc:
    attr_reader :node, :source, :read_class, :write_class, :arguments

    def initialize(node, source, read_class, write_class, *arguments)
      @node = node
      @source = source
      @read_class = read_class
      @write_class = write_class
      @arguments = arguments
    end

    # Desugar `x += y` to `x = x + y`
    def compile
      write_class.new(
        source,
        *arguments,
        node.name_loc,
        CallNode.new(
          source,
          0,
          read_class.new(source, *arguments, node.name_loc),
          nil,
          node.operator_loc.slice.chomp("=").to_sym,
          node.operator_loc.copy(length: node.operator_loc.length - 1),
          nil,
          ArgumentsNode.new(source, 0, [node.value], node.value.location),
          nil,
          nil,
          node.location
        ),
        node.operator_loc.copy(start_offset: node.operator_loc.end_offset - 1, length: 1),
        node.location
      )
    end
  end

  class DesugarOrWriteNode # :nodoc:
    attr_reader :node, :source, :read_class, :write_class, :arguments

    def initialize(node, source, read_class, write_class, *arguments)
      @node = node
      @source = source
      @read_class = read_class
      @write_class = write_class
      @arguments = arguments
    end

    # Desugar `x ||= y` to `x || x = y`
    def compile
      OrNode.new(
        source,
        read_class.new(source, *arguments, node.name_loc),
        write_class.new(source, *arguments, node.name_loc, node.value, node.operator_loc, node.location),
        node.operator_loc,
        node.location
      )
    end
  end

  private_constant :DesugarAndWriteNode, :DesugarOrWriteNode, :DesugarOrWriteDefinedNode, :DesugarOperatorWriteNode

  class ClassVariableAndWriteNode
    def desugar # :nodoc:
      DesugarAndWriteNode.new(self, source, ClassVariableReadNode, ClassVariableWriteNode, name).compile
    end
  end

  class ClassVariableOrWriteNode
    def desugar # :nodoc:
      DesugarOrWriteDefinedNode.new(self, source, ClassVariableReadNode, ClassVariableWriteNode, name).compile
    end
  end

  class ClassVariableOperatorWriteNode
    def desugar # :nodoc:
      DesugarOperatorWriteNode.new(self, source, ClassVariableReadNode, ClassVariableWriteNode, name).compile
    end
  end

  class ConstantAndWriteNode
    def desugar # :nodoc:
      DesugarAndWriteNode.new(self, source, ConstantReadNode, ConstantWriteNode, name).compile
    end
  end

  class ConstantOrWriteNode
    def desugar # :nodoc:
      DesugarOrWriteDefinedNode.new(self, source, ConstantReadNode, ConstantWriteNode, name).compile
    end
  end

  class ConstantOperatorWriteNode
    def desugar # :nodoc:
      DesugarOperatorWriteNode.new(self, source, ConstantReadNode, ConstantWriteNode, name).compile
    end
  end

  class GlobalVariableAndWriteNode
    def desugar # :nodoc:
      DesugarAndWriteNode.new(self, source, GlobalVariableReadNode, GlobalVariableWriteNode, name).compile
    end
  end

  class GlobalVariableOrWriteNode
    def desugar # :nodoc:
      DesugarOrWriteDefinedNode.new(self, source, GlobalVariableReadNode, GlobalVariableWriteNode, name).compile
    end
  end

  class GlobalVariableOperatorWriteNode
    def desugar # :nodoc:
      DesugarOperatorWriteNode.new(self, source, GlobalVariableReadNode, GlobalVariableWriteNode, name).compile
    end
  end

  class InstanceVariableAndWriteNode
    def desugar # :nodoc:
      DesugarAndWriteNode.new(self, source, InstanceVariableReadNode, InstanceVariableWriteNode, name).compile
    end
  end

  class InstanceVariableOrWriteNode
    def desugar # :nodoc:
      DesugarOrWriteNode.new(self, source, InstanceVariableReadNode, InstanceVariableWriteNode, name).compile
    end
  end

  class InstanceVariableOperatorWriteNode
    def desugar # :nodoc:
      DesugarOperatorWriteNode.new(self, source, InstanceVariableReadNode, InstanceVariableWriteNode, name).compile
    end
  end

  class LocalVariableAndWriteNode
    def desugar # :nodoc:
      DesugarAndWriteNode.new(self, source, LocalVariableReadNode, LocalVariableWriteNode, name, depth).compile
    end
  end

  class LocalVariableOrWriteNode
    def desugar # :nodoc:
      DesugarOrWriteNode.new(self, source, LocalVariableReadNode, LocalVariableWriteNode, name, depth).compile
    end
  end

  class LocalVariableOperatorWriteNode
    def desugar # :nodoc:
      DesugarOperatorWriteNode.new(self, source, LocalVariableReadNode, LocalVariableWriteNode, name, depth).compile
    end
  end

  # DesugarCompiler is a compiler that desugars Ruby code into a more primitive
  # form. This is useful for consumers that want to deal with fewer node types.
  class DesugarCompiler < MutationCompiler
    # @@foo &&= bar
    #
    # becomes
    #
    # @@foo && @@foo = bar
    def visit_class_variable_and_write_node(node)
      node.desugar
    end

    # @@foo ||= bar
    #
    # becomes
    #
    # defined?(@@foo) ? @@foo : @@foo = bar
    def visit_class_variable_or_write_node(node)
      node.desugar
    end

    # @@foo += bar
    #
    # becomes
    #
    # @@foo = @@foo + bar
    def visit_class_variable_operator_write_node(node)
      node.desugar
    end

    # Foo &&= bar
    #
    # becomes
    #
    # Foo && Foo = bar
    def visit_constant_and_write_node(node)
      node.desugar
    end

    # Foo ||= bar
    #
    # becomes
    #
    # defined?(Foo) ? Foo : Foo = bar
    def visit_constant_or_write_node(node)
      node.desugar
    end

    # Foo += bar
    #
    # becomes
    #
    # Foo = Foo + bar
    def visit_constant_operator_write_node(node)
      node.desugar
    end

    # $foo &&= bar
    #
    # becomes
    #
    # $foo && $foo = bar
    def visit_global_variable_and_write_node(node)
      node.desugar
    end

    # $foo ||= bar
    #
    # becomes
    #
    # defined?($foo) ? $foo : $foo = bar
    def visit_global_variable_or_write_node(node)
      node.desugar
    end

    # $foo += bar
    #
    # becomes
    #
    # $foo = $foo + bar
    def visit_global_variable_operator_write_node(node)
      node.desugar
    end

    # @foo &&= bar
    #
    # becomes
    #
    # @foo && @foo = bar
    def visit_instance_variable_and_write_node(node)
      node.desugar
    end

    # @foo ||= bar
    #
    # becomes
    #
    # @foo || @foo = bar
    def visit_instance_variable_or_write_node(node)
      node.desugar
    end

    # @foo += bar
    #
    # becomes
    #
    # @foo = @foo + bar
    def visit_instance_variable_operator_write_node(node)
      node.desugar
    end

    # foo &&= bar
    #
    # becomes
    #
    # foo && foo = bar
    def visit_local_variable_and_write_node(node)
      node.desugar
    end

    # foo ||= bar
    #
    # becomes
    #
    # foo || foo = bar
    def visit_local_variable_or_write_node(node)
      node.desugar
    end

    # foo += bar
    #
    # becomes
    #
    # foo = foo + bar
    def visit_local_variable_operator_write_node(node)
      node.desugar
    end
  end
end
