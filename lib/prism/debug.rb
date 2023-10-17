# frozen_string_literal: true

module Prism
  # This module is used for testing and debugging and is not meant to be used by
  # consumers of this library.
  module Debug
    class ISeq
      attr_reader :parts

      def initialize(parts)
        @parts = parts
      end

      def type
        parts[0]
      end

      def local_table
        parts[10]
      end

      def instructions
        parts[13]
      end

      def each_child
        instructions.each do |instruction|
          # Only look at arrays. Other instructions are line numbers or
          # tracepoint events.
          next unless instruction.is_a?(Array)

          instruction.each do |opnd|
            # Only look at arrays. Other operands are literals.
            next unless opnd.is_a?(Array)

            # Only look at instruction sequences. Other operands are literals.
            next unless opnd[0] == "YARVInstructionSequence/SimpleDataFormat"

            yield ISeq.new(opnd)
          end
        end
      end
    end

    # For the given source, compiles with CRuby and returns a list of all of the
    # sets of local variables that were encountered.
    def self.cruby_locals(source)
      verbose, $VERBOSE = $VERBOSE, nil

      begin
        locals = []
        stack = [ISeq.new(RubyVM::InstructionSequence.compile(source).to_a)]

        while (iseq = stack.pop)
          # For some reason, CRuby occasionally pushes this special local
          # variable when there are splat arguments. We get rid of that here.
          locals << (iseq.local_table - [:"#arg_rest"])
          iseq.each_child { |child| stack << child }
        end

        locals
      ensure
        $VERBOSE = verbose
      end
    end

    AnonymousLocal = Object.new

    # For the given source, parses with prism and returns a list of all of the
    # sets of local variables that were encountered.
    def self.prism_locals(source)
      locals = []
      stack = [Prism.parse(source).value]

      while (node = stack.pop)
        case node
        when BlockNode, DefNode, LambdaNode
          names = node.locals

          params = node.parameters
          params = params&.parameters unless node.is_a?(DefNode)

          # prism places parameters in the same order that they appear in the
          # source. CRuby places them in the order that they need to appear
          # according to their own internal calling convention. We mimic that
          # order here so that we can compare properly.
          if params
            sorted = [
              *params.requireds.map do |required|
                if required.is_a?(RequiredParameterNode)
                  required.name
                else
                  AnonymousLocal
                end
              end,
              *params.optionals.map(&:name),
              *((params.rest.name || :*) if params.rest && params.rest.operator != ","),
              *params.posts.map do |post|
                if post.is_a?(RequiredParameterNode)
                  post.name
                else
                  AnonymousLocal
                end
              end,
              *params.keywords.reject(&:value).map(&:name),
              *params.keywords.select(&:value).map(&:name)
            ]

            sorted << AnonymousLocal if params.keywords.any?

            # Recurse down the parameter tree to find any destructured
            # parameters and add them after the other parameters.
            param_stack = params.requireds.concat(params.posts).grep(RequiredDestructuredParameterNode).reverse
            while (param = param_stack.pop)
              case param
              when RequiredDestructuredParameterNode
                param_stack.concat(param.parameters.reverse)
              when RequiredParameterNode
                sorted << param.name
              when SplatNode
                sorted << param.expression.name if param.expression
              end
            end

            names = sorted.concat(names - sorted)
          end

          names.map!.with_index do |name, index|
            if name == AnonymousLocal
              names.length - index + 1
            else
              name
            end
          end

          locals << names
        when ClassNode, ModuleNode, ProgramNode, SingletonClassNode
          locals << node.locals
        when ForNode
          locals << [2]
        when PostExecutionNode
          locals.push([], [])
        when InterpolatedRegularExpressionNode
          locals << [] if node.once?
        end

        stack.concat(node.compact_child_nodes)
      end

      locals
    end

    def self.newlines(source)
      Prism.parse(source).source.offsets
    end

    def self.parse_serialize_file(filepath)
      parse_serialize_file_metadata(filepath, [filepath.bytesize, filepath.b, 0].pack("LA*L"))
    end
  end
end
