# frozen_string_literal: true

module YARP
  # A pattern is an object that wraps a Ruby pattern matching expression. The
  # expression would normally be passed to an `in` clause within a `case`
  # expression or a rightward assignment expression. For example, in the
  # following snippet:
  #
  #     case node
  #     in ConstantPathNode[ConstantReadNode[name: :YARP], ConstantReadNode[name: :Pattern]]
  #     end
  #
  # the pattern is the `ConstantPathNode[...]` expression.
  #
  # The pattern gets compiled into an object that responds to #call by running
  # the #compile method. This method itself will run back through YARP to
  # parse the expression into a tree, then walk the tree to generate the
  # necessary callable objects. For example, if you wanted to compile the
  # expression above into a callable, you would:
  #
  #     callable = YARP::Pattern.new("ConstantPathNode[ConstantReadNode[name: :YARP], ConstantReadNode[name: :Pattern]]").compile
  #     callable.call(node)
  #
  # The callable object returned by #compile is guaranteed to respond to #call
  # with a single argument, which is the node to match against. It also is
  # guaranteed to respond to #===, which means it itself can be used in a `case`
  # expression, as in:
  #
  #     case node
  #     when callable
  #     end
  #
  # If the query given to the initializer cannot be compiled into a valid
  # matcher (either because of a syntax error or because it is using syntax we
  # do not yet support) then a YARP::Pattern::CompilationError will be
  # raised.
  class Pattern
    # Raised when the query given to a pattern is either invalid Ruby syntax or
    # is using syntax that we don't yet support.
    class CompilationError < StandardError
      def initialize(repr)
        super(<<~ERROR)
          YARP was unable to compile the pattern you provided into a usable
          expression. It failed on to understand the node represented by:

          #{repr}

          Note that not all syntax supported by Ruby's pattern matching syntax
          is also supported by YARP's patterns. If you're using some syntax
          that you believe should be supported, please open an issue on
          GitHub at https://github.com/ruby/yarp/issues/new.
        ERROR
      end
    end

    attr_reader :query

    def initialize(query)
      @query = query
      @compiled = nil
    end

    def compile
      result = YARP.parse("case nil\nin #{query}\nend")
      compile_node(result.value.statements.body.last.conditions.last.pattern)
    end

    def scan(root)
      return to_enum(__method__, root) unless block_given?

      @compiled ||= compile
      queue = [root]

      while (node = queue.shift)
        yield node if @compiled.call(node)
        queue.concat(node.child_nodes.compact)
      end
    end

    private

    # Shortcut for combining two procs into one that returns true if both return
    # true.
    def combine_and(left, right)
      ->(other) { left.call(other) && right.call(other) }
    end

    # Shortcut for combining two procs into one that returns true if either
    # returns true.
    def combine_or(left, right)
      ->(other) { left.call(other) || right.call(other) }
    end

    # Raise an error because the given node is not supported.
    def compile_error(node)
      raise CompilationError, node.inspect
    end

    # in [foo, bar, baz]
    def compile_array_pattern_node(node)
      compile_error(node) if !node.rest.nil? || node.posts.any?

      constant = node.constant
      compiled_constant = compile_node(constant) if constant

      preprocessed = node.requireds.map { |required| compile_node(required) }

      compiled_requireds = ->(other) do
        deconstructed = other.deconstruct

        deconstructed.length == preprocessed.length &&
          preprocessed
            .zip(deconstructed)
            .all? { |(matcher, value)| matcher.call(value) }
      end

      if compiled_constant
        combine_and(compiled_constant, compiled_requireds)
      else
        compiled_requireds
      end
    end

    # in foo | bar
    def compile_alternation_pattern_node(node)
      combine_or(compile_node(node.left), compile_node(node.right))
    end

    # in YARP::ConstantReadNode
    def compile_constant_path_node(node)
      parent = node.parent

      if parent.is_a?(ConstantReadNode) && parent.slice == "YARP"
        compile_node(node.child)
      else
        compile_error(node)
      end
    end

    # in ConstantReadNode
    # in String
    def compile_constant_read_node(node)
      value = node.slice

      if YARP.const_defined?(value, false)
        clazz = YARP.const_get(value)

        ->(other) { clazz === other }
      elsif Object.const_defined?(value, false)
        clazz = Object.const_get(value)

        ->(other) { clazz === other }
      else
        compile_error(node)
      end
    end

    # in InstanceVariableReadNode[name: Symbol]
    # in { name: Symbol }
    def compile_hash_pattern_node(node)
      compile_error(node) unless node.kwrest.nil?
      compiled_constant = compile_node(node.constant) if node.constant

      preprocessed =
        node.assocs.to_h do |assoc|
          [assoc.key.unescaped.to_sym, compile_node(assoc.value)]
        end

      compiled_keywords = ->(other) do
        deconstructed = other.deconstruct_keys(preprocessed.keys)

        preprocessed.all? do |keyword, matcher|
          deconstructed.key?(keyword) && matcher.call(deconstructed[keyword])
        end
      end

      if compiled_constant
        combine_and(compiled_constant, compiled_keywords)
      else
        compiled_keywords
      end
    end

    # in nil
    def compile_nil_node(node)
      ->(attribute) { attribute.nil? }
    end

    # in /foo/
    def compile_regular_expression_node(node)
      regexp = Regexp.new(node.unescaped, node.closing[1..])

      ->(attribute) { regexp === attribute }
    end

    # in ""
    # in "foo"
    def compile_string_node(node)
      string = node.unescaped

      ->(attribute) { string === attribute }
    end

    # in :+
    # in :foo
    def compile_symbol_node(node)
      symbol = node.unescaped.to_sym

      ->(attribute) { symbol === attribute }
    end

    # Compile any kind of node. Dispatch out to the individual compilation
    # methods based on the type of node.
    def compile_node(node)
      case node
      when AlternationPatternNode
        compile_alternation_pattern_node(node)
      when ArrayPatternNode
        compile_array_pattern_node(node)
      when ConstantPathNode
        compile_constant_path_node(node)
      when ConstantReadNode
        compile_constant_read_node(node)
      when HashPatternNode
        compile_hash_pattern_node(node)
      when NilNode
        compile_nil_node(node)
      when RegularExpressionNode
        compile_regular_expression_node(node)
      when StringNode
        compile_string_node(node)
      when SymbolNode
        compile_symbol_node(node)
      else
        compile_error(node)
      end
    end
  end
end
