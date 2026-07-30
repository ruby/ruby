# frozen_string_literal: true

# This test is going to use the RubyVM::InstructionSequence class to compile
# local tables and compare against them to ensure we have the same locals in the
# same order. This is important to guarantee that we compile indices correctly
# on CRuby (in terms of compatibility).
#
# There have also been changes made in other versions of Ruby, so we only want
# to test on the most recent versions.
return if !defined?(RubyVM::InstructionSequence) || RUBY_VERSION < "3.4.0"

# If we're on Ruby 3.4.0 and the default parser is Prism, then there is no point
# in comparing the locals because they will be the same.
return if RubyVM::InstructionSequence.compile("").to_a[4][:parser] == :prism

# Omit tests if running on a 32-bit machine because there is a bug with how
# Ruby is handling large ISeqs on 32-bit machines
return if RUBY_PLATFORM =~ /i686/

require_relative "test_helper"

module Prism
  class LocalsTest < TestCase
    except = [
      # Skip this fixture because it has a different number of locals because
      # CRuby is eliminating dead code.
      "whitequark/ruby_bug_10653.txt",

      # https://bugs.ruby-lang.org/issues/21168#note-5
      "command_method_call_2.txt",

      # https://bugs.ruby-lang.org/issues/21669
      "4.1/void_value.txt",

      # https://bugs.ruby-lang.org/issues/19107
      "4.1/trailing_comma_after_method_arguments.txt",
    ]

    Fixture.each_for_current_ruby(except: except) do |fixture|
      define_method(fixture.test_name) { assert_locals(fixture) }
    end

    def setup
      @previous_default_external = Encoding.default_external
      ignore_warnings { Encoding.default_external = Encoding::UTF_8 }
    end

    def teardown
      ignore_warnings { Encoding.default_external = @previous_default_external }
    end

    private

    def assert_locals(fixture)
      source = fixture.read

      expected = cruby_locals(source)
      actual = prism_locals(source)

      assert_equal(expected, actual)
    end

    # A wrapper around a RubyVM::InstructionSequence that provides a more
    # convenient interface for accessing parts of the iseq.
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

      def catch_table
        parts[12]
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

        # The handler for a rescue clause is compiled into its own iseq that is
        # reachable only through the catch table. Its local table only ever
        # holds the implicit `$!` error variable (rescue clauses do not
        # introduce user locals of their own -- `rescue => e` puts `e` in the
        # enclosing scope), and prism does not model it as a scope, so we treat
        # it as transparent and descend straight into any iseqs nested within
        # it (e.g. a block or an `END {}` inside a rescue clause). Only
        # `:rescue` entries are followed: `:break`/`:next`/`:redo`/`:retry`
        # entries either have no iseq or reference one already reachable through
        # the instructions, and `:ensure` bodies are compiled inline.
        catch_table.each do |entry|
          ISeq.new(entry[1]).each_child { |child| yield child } if entry[0] == :rescue && entry[1].is_a?(Array)
        end
      end
    end

    # Used to hold the place of a local that will be in the local table but
    # cannot be accessed directly from the source code. For example, the
    # iteration variable in a for loop or the positional parameter on a method
    # definition that is destructured.
    AnonymousLocal = Object.new

    # Emulates one block iseq synthesized for a for-comprehension iterator:
    # the flat_map/map block (when comprehension is set, along with the
    # iterator's position in it), or the filter block of a guard (when
    # comprehension is nil). Each such block's local table holds the hidden
    # iteration parameter followed by the iterator's locals.
    ForCompScope = Struct.new(:iterator, :comprehension, :position)

    # For the given source, compiles with CRuby and returns a list of all of the
    # sets of local variables that were encountered.
    def cruby_locals(source)
      locals = [] #: Array[Array[Symbol | Integer]]
      stack = [ISeq.new(ignore_warnings { RubyVM::InstructionSequence.compile(source) }.to_a)]

      while (iseq = stack.pop)
        names = [*iseq.local_table]
        names.map!.with_index do |name, index|
          # When an anonymous local variable is present in the iseq's local
          # table, it is represented as the stack offset from the top.
          # However, when these are dumped to binary and read back in, they
          # are replaced with the symbol :#arg_rest. To consistently handle
          # this, we replace them here with their index.
          if name == :"#arg_rest"
            names.length - index + 1
          else
            name
          end
        end

        locals << names
        iseq.each_child { |child| stack << child }
      end

      locals
    end

    # For the given source, parses with prism and returns a list of all of the
    # sets of local variables that were encountered.
    def prism_locals(source)
      locals = [] #: Array[Array[Symbol | Integer]]
      stack = [Prism.parse(source).value] #: Array[Prism::node]

      while (node = stack.pop)
        if node.is_a?(ForCompScope)
          names = [AnonymousLocal, *node.iterator.locals]
          names.map!.with_index do |name, index|
            name == AnonymousLocal ? names.length - index + 1 : name
          end
          locals << names

          if node.comprehension.nil?
            # A guard's filter block: its body is the guard expression.
            stack << node.iterator.guard
          elsif node.position + 1 < node.comprehension.iterators.length
            # The block's body is the next iterator's send chain.
            stack.concat(for_comp_children(node.comprehension, node.position + 1))
          elsif node.comprehension.statements
            # The innermost block: its body is the user statements.
            stack << node.comprehension.statements
          end
          next
        end

        case node
        when BlockNode, DefNode, LambdaNode
          names = node.locals
          params = nil

          if node.is_a?(DefNode)
            params = node.parameters
          elsif node.parameters.is_a?(NumberedParametersNode)
            # nothing
          elsif node.parameters.is_a?(ItParametersNode)
            names.unshift(AnonymousLocal)
          else
            params = node.parameters&.parameters
          end

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
              *((params.rest.name || :*) if params.rest && !params.rest.is_a?(ImplicitRestNode)),
              *params.posts.map do |post|
                if post.is_a?(RequiredParameterNode)
                  post.name
                else
                  AnonymousLocal
                end
              end,
              *params.keywords.grep(RequiredKeywordParameterNode).map(&:name),
              *params.keywords.grep(OptionalKeywordParameterNode).map(&:name),
            ]

            sorted << AnonymousLocal if params.keywords.any?

            if params.keyword_rest.is_a?(ForwardingParameterNode)
              if sorted.length == 0
                sorted.push(:"...")
              else
                sorted.push(:*, :**, :&, :"...")
              end
            elsif params.keyword_rest.is_a?(KeywordRestParameterNode)
              sorted << (params.keyword_rest.name || :**)
            end

            # Recurse down the parameter tree to find any destructured
            # parameters and add them after the other parameters.
            param_stack = params.requireds.concat(params.posts).grep(MultiTargetNode).reverse
            while (param = param_stack.pop)
              case param
              when MultiTargetNode
                param_stack.concat(param.rights.reverse)
                param_stack << param.rest if param.rest&.expression && !sorted.include?(param.rest.expression.name)
                param_stack.concat(param.lefts.reverse)
              when RequiredParameterNode
                sorted << param.name
              when SplatNode
                sorted << param.expression.name
              end
            end

            if params.block.is_a?(BlockParameterNode)
              sorted << (params.block.name || :&)
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
        when ForComprehensionNode
          # The comprehension compiles to filter/flat_map/map sends in the
          # enclosing scope; emulate its synthesized block iseqs instead of
          # traversing the node's children directly.
          stack.concat(for_comp_children(node, 0))
          next
        when PostExecutionNode
          locals.push([], [])
        when InterpolatedRegularExpressionNode
          locals << [] if node.once?
        end

        stack.concat(node.compact_child_nodes)
      end

      locals
    end

    # The stack entries for the comprehension's iterator at position, in the
    # order the enclosing instruction sequence contains them: the collection
    # is compiled in the enclosing scope, then the guard's filter block (if
    # any), then the flat_map/map block.
    def for_comp_children(node, position)
      iterator = node.iterators[position]
      children = [iterator.collection]
      children << ForCompScope.new(iterator, nil, nil) if iterator.guard
      children << ForCompScope.new(iterator, node, position)
      children
    end
  end
end
