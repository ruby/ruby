# frozen_string_literal: true
# :markup: markdown
#--
# rbs_inline: enabled

module Prism
  # Finds the Prism AST node corresponding to a given Method, UnboundMethod,
  # Proc, or Thread::Backtrace::Location. On CRuby, uses node_id from the
  # instruction sequence for an exact match. On other implementations, falls
  # back to best-effort matching by source location line number.
  #
  # This module is autoloaded so that programs that don't use Prism.find don't
  # pay for its definition.
  module NodeFind # :nodoc:
    # Find the node for the given callable or backtrace location.
    #--
    #: (Method | UnboundMethod | Proc | Thread::Backtrace::Location callable, bool rubyvm) -> Node?
    def self.find(callable, rubyvm)
      case callable
      when Proc
        if rubyvm
          RubyVMCallableFind.new.find(callable)
        elsif callable.lambda?
          LineLambdaFind.new.find(callable)
        else
          LineProcFind.new.find(callable)
        end
      when Method, UnboundMethod
        if rubyvm
          RubyVMCallableFind.new.find(callable)
        else
          LineMethodFind.new.find(callable)
        end
      when Thread::Backtrace::Location
        if rubyvm
          RubyVMBacktraceLocationFind.new.find(callable)
        else
          LineBacktraceLocationFind.new.find(callable)
        end
      else
        raise ArgumentError, "Expected a Method, UnboundMethod, Proc, or Thread::Backtrace::Location, got #{callable.class}"
      end
    end

    # Base class that handles parsing a file.
    class Find
      private

      # Parse the given file path, returning a ParseResult or nil.
      #--
      #: (String? file) -> ParseResult?
      def parse_file(file)
        return unless file && File.readable?(file)
        result = Prism.parse_file(file)
        result if result.success?
      end
    end

    # Finds the AST node for a Method, UnboundMethod, or Proc using the node_id
    # from the instruction sequence.
    class RubyVMCallableFind < Find
      # Find the node for the given callable using the ISeq node_id.
      #--
      #: (Method | UnboundMethod | Proc callable) -> Node?
      def find(callable)
        return unless (source_location = callable.source_location)
        return unless (result = parse_file(source_location[0]))
        return unless (iseq = RubyVM::InstructionSequence.of(callable))

        header = iseq.to_a[4]
        return unless header[:parser] == :prism

        result.value.find { |node| node.node_id == header[:node_id] }
      end
    end

    # Finds the AST node for a Thread::Backtrace::Location using the node_id
    # from the backtrace location.
    class RubyVMBacktraceLocationFind < Find
      # Find the node for the given backtrace location using node_id.
      #--
      #: (Thread::Backtrace::Location location) -> Node?
      def find(location)
        file = location.absolute_path || location.path
        return unless (result = parse_file(file))
        return unless RubyVM::AbstractSyntaxTree.respond_to?(:node_id_for_backtrace_location)

        node_id = RubyVM::AbstractSyntaxTree.node_id_for_backtrace_location(location)

        result.value.find { |node| node.node_id == node_id }
      end
    end

    # Finds the AST node for a Method or UnboundMethod using best-effort line
    # matching. Used on non-CRuby implementations.
    class LineMethodFind < Find
      # Find the node for the given method by matching on name and line.
      #--
      #: (Method | UnboundMethod callable) -> Node?
      def find(callable)
        return unless (source_location = callable.source_location)
        return unless (result = parse_file(source_location[0]))

        name = callable.name
        start_line = source_location[1]

        result.value.find do |node|
          case node
          when DefNode
            node.name == name && node.location.start_line == start_line
          when CallNode
            node.block.is_a?(BlockNode) && node.location.start_line == start_line
          else
            false
          end
        end
      end
    end

    # Finds the AST node for a lambda using best-effort line matching. Used
    # on non-CRuby implementations.
    class LineLambdaFind < Find
      # Find the node for the given lambda by matching on line.
      #--
      #: (Proc callable) -> Node?
      def find(callable)
        return unless (source_location = callable.source_location)
        return unless (result = parse_file(source_location[0]))

        start_line = source_location[1]

        result.value.find do |node|
          case node
          when LambdaNode
            node.location.start_line == start_line
          when CallNode
            node.block.is_a?(BlockNode) && node.location.start_line == start_line
          else
            false
          end
        end
      end
    end

    # Finds the AST node for a non-lambda Proc using best-effort line
    # matching. Used on non-CRuby implementations.
    class LineProcFind < Find
      # Find the node for the given proc by matching on line.
      #--
      #: (Proc callable) -> Node?
      def find(callable)
        return unless (source_location = callable.source_location)
        return unless (result = parse_file(source_location[0]))

        start_line = source_location[1]

        result.value.find do |node|
          case node
          when ForNode
            node.location.start_line == start_line
          when CallNode
            node.block.is_a?(BlockNode) && node.location.start_line == start_line
          else
            false
          end
        end
      end
    end

    # Finds the AST node for a Thread::Backtrace::Location using best-effort
    # line matching. Used on non-CRuby implementations.
    class LineBacktraceLocationFind < Find
      # Find the node for the given backtrace location by matching on line.
      #--
      #: (Thread::Backtrace::Location location) -> Node?
      def find(location)
        file = location.absolute_path || location.path
        return unless (result = parse_file(file))

        start_line = location.lineno
        result.value.find { |node| node.location.start_line == start_line }
      end
    end
  end
end
