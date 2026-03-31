# frozen_string_literal: true
# :markup: markdown
#--
# rbs_inline: enabled

module Prism
  class DesugarAndWriteNode # :nodoc:
    include DSL

    attr_reader :node #: ClassVariableAndWriteNode | ConstantAndWriteNode | GlobalVariableAndWriteNode | InstanceVariableAndWriteNode | LocalVariableAndWriteNode
    attr_reader :default_source #: Source
    attr_reader :read_class, :write_class #: Symbol
    attr_reader :arguments #: Hash[Symbol, untyped]

    #: ((ClassVariableAndWriteNode | ConstantAndWriteNode | GlobalVariableAndWriteNode | InstanceVariableAndWriteNode | LocalVariableAndWriteNode) node, Source default_source, Symbol read_class, Symbol write_class, **untyped arguments) -> void
    def initialize(node, default_source, read_class, write_class, **arguments)
      @node = node
      @default_source = default_source
      @read_class = read_class
      @write_class = write_class
      @arguments = arguments
    end

    # Desugar `x &&= y` to `x && x = y`
    #--
    #: () -> node
    def compile
      and_node(
        location: node.location,
        left: public_send(read_class, location: node.name_loc, **arguments),
        right: public_send(
          write_class,
          location: node.location,
          **arguments,
          name_loc: node.name_loc,
          value: node.value,
          operator_loc: node.operator_loc
        ),
        operator_loc: node.operator_loc
      )
    end
  end

  class DesugarOrWriteDefinedNode # :nodoc:
    include DSL

    attr_reader :node #: ClassVariableOrWriteNode | ConstantOrWriteNode | GlobalVariableOrWriteNode
    attr_reader :default_source #: Source
    attr_reader :read_class, :write_class #: Symbol
    attr_reader :arguments #: Hash[Symbol, untyped]

    #: ((ClassVariableOrWriteNode | ConstantOrWriteNode | GlobalVariableOrWriteNode) node, Source default_source, Symbol read_class, Symbol write_class, **untyped arguments) -> void
    def initialize(node, default_source, read_class, write_class, **arguments)
      @node = node
      @default_source = default_source
      @read_class = read_class
      @write_class = write_class
      @arguments = arguments
    end

    # Desugar `x ||= y` to `defined?(x) ? x : x = y`
    #--
    #: () -> node
    def compile
      if_node(
        location: node.location,
        if_keyword_loc: node.operator_loc,
        predicate: defined_node(
          location: node.name_loc,
          value: public_send(read_class, location: node.name_loc, **arguments),
          keyword_loc: node.operator_loc
        ),
        then_keyword_loc: node.operator_loc,
        statements: statements_node(
          location: node.location,
          body: [public_send(read_class, location: node.name_loc, **arguments)]
        ),
        subsequent: else_node(
          location: node.location,
          else_keyword_loc: node.operator_loc,
          statements: statements_node(
            location: node.location,
            body: [
              public_send(
                write_class,
                location: node.location,
                **arguments,
                name_loc: node.name_loc,
                value: node.value,
                operator_loc: node.operator_loc
              )
            ]
          ),
          end_keyword_loc: node.operator_loc
        ),
        end_keyword_loc: node.operator_loc
      )
    end
  end

  class DesugarOperatorWriteNode # :nodoc:
    include DSL

    attr_reader :node #: ClassVariableOperatorWriteNode | ConstantOperatorWriteNode | GlobalVariableOperatorWriteNode | InstanceVariableOperatorWriteNode | LocalVariableOperatorWriteNode
    attr_reader :default_source #: Source
    attr_reader :read_class, :write_class #: Symbol
    attr_reader :arguments #: Hash[Symbol, untyped]

    #: ((ClassVariableOperatorWriteNode | ConstantOperatorWriteNode | GlobalVariableOperatorWriteNode | InstanceVariableOperatorWriteNode | LocalVariableOperatorWriteNode) node, Source default_source, Symbol read_class, Symbol write_class, **untyped arguments) -> void
    def initialize(node, default_source, read_class, write_class, **arguments)
      @node = node
      @default_source = default_source
      @read_class = read_class
      @write_class = write_class
      @arguments = arguments
    end

    # Desugar `x += y` to `x = x + y`
    #--
    #: () -> node
    def compile
      binary_operator_loc = node.binary_operator_loc.chop

      public_send(
        write_class,
        location: node.location,
        **arguments,
        name_loc: node.name_loc,
        value: call_node(
          location: node.location,
          receiver: public_send(
            read_class,
            location: node.name_loc,
            **arguments
          ),
          name: binary_operator_loc.slice.to_sym,
          message_loc: binary_operator_loc,
          arguments: arguments_node(
            location: node.value.location,
            arguments: [node.value]
          )
        ),
        operator_loc: node.binary_operator_loc.copy(
          start_offset: node.binary_operator_loc.end_offset - 1,
          length: 1
        )
      )
    end
  end

  class DesugarOrWriteNode # :nodoc:
    include DSL

    attr_reader :node #: InstanceVariableOrWriteNode | LocalVariableOrWriteNode
    attr_reader :default_source #: Source
    attr_reader :read_class, :write_class #: Symbol
    attr_reader :arguments #: Hash[Symbol, untyped]

    #: ((InstanceVariableOrWriteNode | LocalVariableOrWriteNode) node, Source default_source, Symbol read_class, Symbol write_class, **untyped arguments) -> void
    def initialize(node, default_source, read_class, write_class, **arguments)
      @node = node
      @default_source = default_source
      @read_class = read_class
      @write_class = write_class
      @arguments = arguments
    end

    # Desugar `x ||= y` to `x || x = y`
    #--
    #: () -> node
    def compile
      or_node(
        location: node.location,
        left: public_send(read_class, location: node.name_loc, **arguments),
        right: public_send(
          write_class,
          location: node.location,
          **arguments,
          name_loc: node.name_loc,
          value: node.value,
          operator_loc: node.operator_loc
        ),
        operator_loc: node.operator_loc
      )
    end
  end

  private_constant :DesugarAndWriteNode, :DesugarOrWriteNode, :DesugarOrWriteDefinedNode, :DesugarOperatorWriteNode

  class ClassVariableAndWriteNode
    #: () -> node
    def desugar # :nodoc:
      DesugarAndWriteNode.new(self, source, :class_variable_read_node, :class_variable_write_node, name: name).compile
    end
  end

  class ClassVariableOrWriteNode
    #: () -> node
    def desugar # :nodoc:
      DesugarOrWriteDefinedNode.new(self, source, :class_variable_read_node, :class_variable_write_node, name: name).compile
    end
  end

  class ClassVariableOperatorWriteNode
    #: () -> node
    def desugar # :nodoc:
      DesugarOperatorWriteNode.new(self, source, :class_variable_read_node, :class_variable_write_node, name: name).compile
    end
  end

  class ConstantAndWriteNode
    #: () -> node
    def desugar # :nodoc:
      DesugarAndWriteNode.new(self, source, :constant_read_node, :constant_write_node, name: name).compile
    end
  end

  class ConstantOrWriteNode
    #: () -> node
    def desugar # :nodoc:
      DesugarOrWriteDefinedNode.new(self, source, :constant_read_node, :constant_write_node, name: name).compile
    end
  end

  class ConstantOperatorWriteNode
    #: () -> node
    def desugar # :nodoc:
      DesugarOperatorWriteNode.new(self, source, :constant_read_node, :constant_write_node, name: name).compile
    end
  end

  class GlobalVariableAndWriteNode
    #: () -> node
    def desugar # :nodoc:
      DesugarAndWriteNode.new(self, source, :global_variable_read_node, :global_variable_write_node, name: name).compile
    end
  end

  class GlobalVariableOrWriteNode
    #: () -> node
    def desugar # :nodoc:
      DesugarOrWriteDefinedNode.new(self, source, :global_variable_read_node, :global_variable_write_node, name: name).compile
    end
  end

  class GlobalVariableOperatorWriteNode
    #: () -> node
    def desugar # :nodoc:
      DesugarOperatorWriteNode.new(self, source, :global_variable_read_node, :global_variable_write_node, name: name).compile
    end
  end

  class InstanceVariableAndWriteNode
    #: () -> node
    def desugar # :nodoc:
      DesugarAndWriteNode.new(self, source, :instance_variable_read_node, :instance_variable_write_node, name: name).compile
    end
  end

  class InstanceVariableOrWriteNode
    #: () -> node
    def desugar # :nodoc:
      DesugarOrWriteNode.new(self, source, :instance_variable_read_node, :instance_variable_write_node, name: name).compile
    end
  end

  class InstanceVariableOperatorWriteNode
    #: () -> node
    def desugar # :nodoc:
      DesugarOperatorWriteNode.new(self, source, :instance_variable_read_node, :instance_variable_write_node, name: name).compile
    end
  end

  class LocalVariableAndWriteNode
    #: () -> node
    def desugar # :nodoc:
      DesugarAndWriteNode.new(self, source, :local_variable_read_node, :local_variable_write_node, name: name, depth: depth).compile
    end
  end

  class LocalVariableOrWriteNode
    #: () -> node
    def desugar # :nodoc:
      DesugarOrWriteNode.new(self, source, :local_variable_read_node, :local_variable_write_node, name: name, depth: depth).compile
    end
  end

  class LocalVariableOperatorWriteNode
    #: () -> node
    def desugar # :nodoc:
      DesugarOperatorWriteNode.new(self, source, :local_variable_read_node, :local_variable_write_node, name: name, depth: depth).compile
    end
  end

  # DesugarCompiler is a compiler that desugars Ruby code into a more primitive
  # form. This is useful for consumers that want to deal with fewer node types.
  class DesugarCompiler < MutationCompiler
    # `@@foo &&= bar`
    #
    # becomes
    #
    # `@@foo && @@foo = bar`
    #--
    #: (ClassVariableAndWriteNode node) -> node
    def visit_class_variable_and_write_node(node)
      node.desugar
    end

    # `@@foo ||= bar`
    #
    # becomes
    #
    # `defined?(@@foo) ? @@foo : @@foo = bar`
    #--
    #: (ClassVariableOrWriteNode node) -> node
    def visit_class_variable_or_write_node(node)
      node.desugar
    end

    # `@@foo += bar`
    #
    # becomes
    #
    # `@@foo = @@foo + bar`
    #--
    #: (ClassVariableOperatorWriteNode node) -> node
    def visit_class_variable_operator_write_node(node)
      node.desugar
    end

    # `Foo &&= bar`
    #
    # becomes
    #
    # `Foo && Foo = bar`
    #--
    #: (ConstantAndWriteNode node) -> node
    def visit_constant_and_write_node(node)
      node.desugar
    end

    # `Foo ||= bar`
    #
    # becomes
    #
    # `defined?(Foo) ? Foo : Foo = bar`
    #--
    #: (ConstantOrWriteNode node) -> node
    def visit_constant_or_write_node(node)
      node.desugar
    end

    # `Foo += bar`
    #
    # becomes
    #
    # `Foo = Foo + bar`
    #--
    #: (ConstantOperatorWriteNode node) -> node
    def visit_constant_operator_write_node(node)
      node.desugar
    end

    # `$foo &&= bar`
    #
    # becomes
    #
    # `$foo && $foo = bar`
    #--
    #: (GlobalVariableAndWriteNode node) -> node
    def visit_global_variable_and_write_node(node)
      node.desugar
    end

    # `$foo ||= bar`
    #
    # becomes
    #
    # `defined?($foo) ? $foo : $foo = bar`
    #--
    #: (GlobalVariableOrWriteNode node) -> node
    def visit_global_variable_or_write_node(node)
      node.desugar
    end

    # `$foo += bar`
    #
    # becomes
    #
    # `$foo = $foo + bar`
    #--
    #: (GlobalVariableOperatorWriteNode node) -> node
    def visit_global_variable_operator_write_node(node)
      node.desugar
    end

    # `@foo &&= bar`
    #
    # becomes
    #
    # `@foo && @foo = bar`
    #--
    #: (InstanceVariableAndWriteNode node) -> node
    def visit_instance_variable_and_write_node(node)
      node.desugar
    end

    # `@foo ||= bar`
    #
    # becomes
    #
    # `@foo || @foo = bar`
    #--
    #: (InstanceVariableOrWriteNode node) -> node
    def visit_instance_variable_or_write_node(node)
      node.desugar
    end

    # `@foo += bar`
    #
    # becomes
    #
    # `@foo = @foo + bar`
    #--
    #: (InstanceVariableOperatorWriteNode node) -> node
    def visit_instance_variable_operator_write_node(node)
      node.desugar
    end

    # `foo &&= bar`
    #
    # becomes
    #
    # `foo && foo = bar`
    #--
    #: (LocalVariableAndWriteNode node) -> node
    def visit_local_variable_and_write_node(node)
      node.desugar
    end

    # `foo ||= bar`
    #
    # becomes
    #
    # `foo || foo = bar`
    #--
    #: (LocalVariableOrWriteNode node) -> node
    def visit_local_variable_or_write_node(node)
      node.desugar
    end

    # `foo += bar`
    #
    # becomes
    #
    # `foo = foo + bar`
    #--
    #: (LocalVariableOperatorWriteNode node) -> node
    def visit_local_variable_operator_write_node(node)
      node.desugar
    end
  end
end
