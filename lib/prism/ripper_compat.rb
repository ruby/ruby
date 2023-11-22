# frozen_string_literal: true

require "ripper"

module Prism
  # This class is meant to provide a compatibility layer between prism and
  # Ripper. It functions by parsing the entire tree first and then walking it
  # and executing each of the Ripper callbacks as it goes.
  #
  # This class is going to necessarily be slower than the native Ripper API. It
  # is meant as a stopgap until developers migrate to using prism. It is also
  # meant as a test harness for the prism parser.
  class RipperCompat
    # This class mirrors the ::Ripper::SexpBuilder subclass of ::Ripper that
    # returns the arrays of [type, *children].
    class SexpBuilder < RipperCompat
      private

      Ripper::PARSER_EVENTS.each do |event|
        define_method(:"on_#{event}") do |*args|
          [event, *args]
        end
      end

      Ripper::SCANNER_EVENTS.each do |event|
        define_method(:"on_#{event}") do |value|
          [:"@#{event}", value, [lineno, column]]
        end
      end
    end

    # This class mirrors the ::Ripper::SexpBuilderPP subclass of ::Ripper that
    # returns the same values as ::Ripper::SexpBuilder except with a couple of
    # niceties that flatten linked lists into arrays.
    class SexpBuilderPP < SexpBuilder
      private

      def _dispatch_event_new # :nodoc:
        []
      end

      def _dispatch_event_push(list, item) # :nodoc:
        list << item
        list
      end

      Ripper::PARSER_EVENT_TABLE.each do |event, arity|
        case event
        when /_new\z/
          alias_method :"on_#{event}", :_dispatch_event_new if arity == 0
        when /_add\z/
          alias_method :"on_#{event}", :_dispatch_event_push
        end
      end
    end

    # The source that is being parsed.
    attr_reader :source

    # The current line number of the parser.
    attr_reader :lineno

    # The current column number of the parser.
    attr_reader :column

    # Create a new RipperCompat object with the given source.
    def initialize(source)
      @source = source
      @result = nil
      @lineno = nil
      @column = nil
    end

    ############################################################################
    # Public interface
    ############################################################################

    # True if the parser encountered an error during parsing.
    def error?
      result.errors.any?
    end

    # Parse the source and return the result.
    def parse
      result.value.accept(self) unless error?
    end

    ############################################################################
    # Visitor methods
    ############################################################################

    # This method is responsible for dispatching to the correct visitor method
    # based on the type of the node.
    def visit(node)
      node&.accept(self)
    end

    # Visit a CallNode node.
    def visit_call_node(node)
      if !node.opening_loc && node.arguments.arguments.length == 1
        bounds(node.receiver.location)
        left = visit(node.receiver)

        bounds(node.arguments.arguments.first.location)
        right = visit(node.arguments.arguments.first)

        on_binary(left, source[node.message_loc.start_offset...node.message_loc.end_offset].to_sym, right)
      else
        raise NotImplementedError
      end
    end

    # Visit an IntegerNode node.
    def visit_integer_node(node)
      bounds(node.location)
      on_int(source[node.location.start_offset...node.location.end_offset])
    end

    # Visit a StatementsNode node.
    def visit_statements_node(node)
      bounds(node.location)
      node.body.inject(on_stmts_new) do |stmts, stmt|
        on_stmts_add(stmts, visit(stmt))
      end
    end

    # Visit a token found during parsing.
    def visit_token(node)
      bounds(node.location)

      case node.type
      when :MINUS
        on_op(node.value)
      when :PLUS
        on_op(node.value)
      else
        raise NotImplementedError, "Unknown token: #{node.type}"
      end
    end

    # Visit a ProgramNode node.
    def visit_program_node(node)
      bounds(node.location)
      on_program(visit(node.statements))
    end

    ############################################################################
    # Entrypoints for subclasses
    ############################################################################

    # This is a convenience method that runs the SexpBuilder subclass parser.
    def self.sexp_raw(source)
      SexpBuilder.new(source).parse
    end

    # This is a convenience method that runs the SexpBuilderPP subclass parser.
    def self.sexp(source)
      SexpBuilderPP.new(source).parse
    end

    private

    # This method is responsible for updating lineno and column information
    # to reflect the current node.
    #
    # This method could be drastically improved with some caching on the start
    # of every line, but for now it's good enough.
    def bounds(location)
      start_offset = location.start_offset

      @lineno = source[0..start_offset].count("\n") + 1
      @column = start_offset - (source.rindex("\n", start_offset) || 0)
    end

    # Lazily initialize the parse result.
    def result
      @result ||= Prism.parse(source)
    end

    def _dispatch0; end # :nodoc:
    def _dispatch1(_); end # :nodoc:
    def _dispatch2(_, _); end # :nodoc:
    def _dispatch3(_, _, _); end # :nodoc:
    def _dispatch4(_, _, _, _); end # :nodoc:
    def _dispatch5(_, _, _, _, _); end # :nodoc:
    def _dispatch7(_, _, _, _, _, _, _); end # :nodoc:

    (Ripper::SCANNER_EVENT_TABLE.merge(Ripper::PARSER_EVENT_TABLE)).each do |event, arity|
      alias_method :"on_#{event}", :"_dispatch#{arity}"
    end
  end
end
