# frozen_string_literal: true

require "ripper"
require_relative "ripper/ripper_compiler"

module Prism
  module Translation
    # Note: This integration is not finished, and therefore still has many
    # inconsistencies with Ripper. If you'd like to help out, pull requests would
    # be greatly appreciated!
    #
    # This class is meant to provide a compatibility layer between prism and
    # Ripper. It functions by parsing the entire tree first and then walking it
    # and executing each of the Ripper callbacks as it goes.
    #
    # This class is going to necessarily be slower than the native Ripper API. It
    # is meant as a stopgap until developers migrate to using prism. It is also
    # meant as a test harness for the prism parser.
    #
    # To use this class, you treat `Prism::Translation::Ripper` effectively as you would
    # treat the `Ripper` class.
    class Ripper < RipperCompiler
      # This class mirrors the ::Ripper::SexpBuilder subclass of ::Ripper that
      # returns the arrays of [type, *children].
      class SexpBuilder < Ripper
        private

        ::Ripper::PARSER_EVENTS.each do |event|
          define_method(:"on_#{event}") do |*args|
            [event, *args]
          end
        end

        ::Ripper::SCANNER_EVENTS.each do |event|
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

        ::Ripper::PARSER_EVENT_TABLE.each do |event, arity|
          case event
          when /_new\z/
            alias_method :"on_#{event}", :_dispatch_event_new if arity == 0
          when /_add\z/
            alias_method :"on_#{event}", :_dispatch_event_push
          end
        end
      end

      ############################################################################
      # Public interface
      ############################################################################

      # True if the parser encountered an error during parsing.
      def error?
        result.failure?
      end

      # Parse the source and return the result.
      def parse
        result.magic_comments.each do |magic_comment|
          on_magic_comment(magic_comment.key, magic_comment.value)
        end

        if error?
          result.errors.each do |error|
            on_parse_error(error.message)
          end

          nil
        else
          result.value.accept(self)
        end
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

      alias_method :on_parse_error, :_dispatch1
      alias_method :on_magic_comment, :_dispatch2

      (::Ripper::SCANNER_EVENT_TABLE.merge(::Ripper::PARSER_EVENT_TABLE)).each do |event, arity|
        alias_method :"on_#{event}", :"_dispatch#{arity}"
      end
    end
  end
end
