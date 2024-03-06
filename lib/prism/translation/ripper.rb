# frozen_string_literal: true

require "ripper"

module Prism
  module Translation
    # Note: This integration is not finished, and therefore still has many
    # inconsistencies with Ripper. If you'd like to help out, pull requests
    # would be greatly appreciated!
    #
    # This class is meant to provide a compatibility layer between prism and
    # Ripper. It functions by parsing the entire tree first and then walking it
    # and executing each of the Ripper callbacks as it goes.
    #
    # This class is going to necessarily be slower than the native Ripper API.
    # It is meant as a stopgap until developers migrate to using prism. It is
    # also meant as a test harness for the prism parser.
    #
    # To use this class, you treat `Prism::Translation::Ripper` effectively as
    # you would treat the `Ripper` class.
    class Ripper < Compiler
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

      # A list of all of the Ruby keywords.
      KEYWORDS = [
        "alias",
        "and",
        "begin",
        "BEGIN",
        "break",
        "case",
        "class",
        "def",
        "defined?",
        "do",
        "else",
        "elsif",
        "end",
        "END",
        "ensure",
        "false",
        "for",
        "if",
        "in",
        "module",
        "next",
        "nil",
        "not",
        "or",
        "redo",
        "rescue",
        "retry",
        "return",
        "self",
        "super",
        "then",
        "true",
        "undef",
        "unless",
        "until",
        "when",
        "while",
        "yield",
        "__ENCODING__",
        "__FILE__",
        "__LINE__"
      ]

      # A list of all of the Ruby binary operators.
      BINARY_OPERATORS = [
        :!=,
        :!~,
        :=~,
        :==,
        :===,
        :<=>,
        :>,
        :>=,
        :<,
        :<=,
        :&,
        :|,
        :^,
        :>>,
        :<<,
        :-,
        :+,
        :%,
        :/,
        :*,
        :**
      ]

      private_constant :KEYWORDS, :BINARY_OPERATORS

      # The source that is being parsed.
      attr_reader :source

      # The current line number of the parser.
      attr_reader :lineno

      # The current column number of the parser.
      attr_reader :column

      # Create a new Translation::Ripper object with the given source.
      def initialize(source)
        @source = source
        @result = nil
        @lineno = nil
        @column = nil
      end

      ##########################################################################
      # Public interface
      ##########################################################################

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

      ##########################################################################
      # Entrypoints for subclasses
      ##########################################################################

      # This is a convenience method that runs the SexpBuilder subclass parser.
      def self.sexp_raw(source)
        SexpBuilder.new(source).parse
      end

      # This is a convenience method that runs the SexpBuilderPP subclass parser.
      def self.sexp(source)
        SexpBuilderPP.new(source).parse
      end

      ##########################################################################
      # Visitor methods
      ##########################################################################

      # alias foo bar
      # ^^^^^^^^^^^^^
      def visit_alias_method_node(node)
        new_name = visit(node.new_name)
        old_name = visit(node.old_name)

        bounds(node.location)
        on_alias(new_name, old_name)
      end

      # alias $foo $bar
      # ^^^^^^^^^^^^^^^
      def visit_alias_global_variable_node(node)
        new_name = visit_alias_global_variable_node_value(node.new_name)
        old_name = visit_alias_global_variable_node_value(node.old_name)

        bounds(node.location)
        on_var_alias(new_name, old_name)
      end

      # Visit one side of an alias global variable node.
      private def visit_alias_global_variable_node_value(node)
        bounds(node.location)

        case node
        when BackReferenceReadNode
          on_backref(node.slice)
        when GlobalVariableReadNode
          on_gvar(node.name.to_s)
        else
          raise
        end
      end

      # foo => bar | baz
      #        ^^^^^^^^^
      def visit_alternation_pattern_node(node)
        left = visit(node.left)
        right = visit(node.right)

        bounds(node.location)
        on_binary(left, :|, right)
      end

      # a and b
      # ^^^^^^^
      def visit_and_node(node)
        left = visit(node.left)
        right = visit(node.right)

        bounds(node.location)
        on_binary(left, node.operator.to_sym, right)
      end

      # []
      # ^^
      def visit_array_node(node)
        bounds(node.location)
        elements =
          case node.opening
          when /^%w/
            node.elements.inject(on_qwords_new) do |qwords, element|
              bounds(element.location)
              on_qwords_add(qwords, on_tstring_content(element.content))
            end
          when /^%i/
            node.elements.inject(on_qsymbols_new) do |qsymbols, element|
              bounds(element.location)
              on_qsymbols_add(qsymbols, on_tstring_content(element.value))
            end
          when /^%W/
            node.elements.inject(on_words_new) do |words, element|
              bounds(element.location)
              word =
                if element.is_a?(StringNode)
                  on_word_add(on_word_new, on_tstring_content(element.content))
                else
                  element.parts.inject(on_word_new) do |word, part|
                    word_part =
                      if part.is_a?(StringNode)
                        bounds(part.location)
                        on_tstring_content(part.content)
                      else
                        visit(part)
                      end

                    on_word_add(word, word_part)
                  end
                end

              on_words_add(words, word)
            end
          when /^%I/
            node.elements.inject(on_symbols_new) do |symbols, element|
              bounds(element.location)
              symbol =
                if element.is_a?(SymbolNode)
                  on_word_add(on_word_new, on_tstring_content(element.value))
                else
                  element.parts.inject(on_word_new) do |word, part|
                    word_part =
                      if part.is_a?(StringNode)
                        bounds(part.location)
                        on_tstring_content(part.content)
                      else
                        visit(part)
                      end

                    on_word_add(word, word_part)
                  end
                end

              on_symbols_add(symbols, symbol)
            end
          else
            visit_arguments(node.elements) unless node.elements.empty?
          end

        bounds(node.location)
        on_array(elements)
      end

      # Visit a list of elements, like the elements of an array or arguments.
      private def visit_arguments(elements)
        bounds(elements.first.location)
        elements.inject(on_args_new) do |args, element|
          arg = visit(element)
          bounds(element.location)

          case element
          when BlockArgumentNode
            on_args_add_block(args, arg)
          when SplatNode
            on_args_add_star(args, arg)
          else
            on_args_add(args, arg)
          end
        end
      end

      # foo => [bar]
      #        ^^^^^
      def visit_array_pattern_node(node)
        constant = visit(node.constant)
        requireds = visit_all(node.requireds) if node.requireds.any?
        rest =
          if (rest_node = node.rest).is_a?(SplatNode)
            if rest_node.expression.nil?
              bounds(rest_node.location)
              on_var_field(nil)
            else
              visit(rest_node.expression)
            end
          end

        posts = visit_all(node.posts) if node.posts.any?

        bounds(node.location)
        on_aryptn(constant, requireds, rest, posts)
      end

      # foo(bar)
      #     ^^^
      def visit_arguments_node(node)
        arguments, _ = visit_call_node_arguments(node, nil, false)
        arguments
      end

      # { a: 1 }
      #   ^^^^
      def visit_assoc_node(node)
        key = visit(node.key)
        value = visit(node.value)

        bounds(node.location)
        on_assoc_new(key, value)
      end

      # def foo(**); bar(**); end
      #                  ^^
      #
      # { **foo }
      #   ^^^^^
      def visit_assoc_splat_node(node)
        value = visit(node.value)

        bounds(node.location)
        on_assoc_splat(value)
      end

      # $+
      # ^^
      def visit_back_reference_read_node(node)
        bounds(node.location)
        on_backref(node.slice)
      end

      # begin end
      # ^^^^^^^^^
      def visit_begin_node(node)
        clauses = visit_begin_node_clauses(node.begin_keyword_loc, node, false)

        bounds(node.location)
        on_begin(clauses)
      end

      # Visit the clauses of a begin node to form an on_bodystmt call.
      private def visit_begin_node_clauses(location, node, allow_newline)
        statements =
          if node.statements.nil?
            on_stmts_add(on_stmts_new, on_void_stmt)
          else
            body = node.statements.body
            body.unshift(nil) if void_stmt?(location, node.statements.body[0].location, allow_newline)

            bounds(node.statements.location)
            visit_statements_node_body(body)
          end

        rescue_clause = visit(node.rescue_clause)
        else_clause =
          unless (else_clause_node = node.else_clause).nil?
            else_statements =
              if else_clause_node.statements.nil?
                [nil]
              else
                body = else_clause_node.statements.body
                body.unshift(nil) if void_stmt?(else_clause_node.else_keyword_loc, else_clause_node.statements.body[0].location, allow_newline)
                body
              end

            bounds(else_clause_node.location)
            visit_statements_node_body(else_statements)
          end
        ensure_clause = visit(node.ensure_clause)

        bounds(node.location)
        on_bodystmt(statements, rescue_clause, else_clause, ensure_clause)
      end

      # Visit the body of a structure that can have either a set of statements
      # or statements wrapped in rescue/else/ensure.
      private def visit_body_node(location, node, allow_newline = false)
        case node
        when nil
          bounds(location)
          on_bodystmt(visit_statements_node_body([nil]), nil, nil, nil)
        when StatementsNode
          body = [*node.body]
          body.unshift(nil) if void_stmt?(location, body[0].location, allow_newline)
          stmts = visit_statements_node_body(body)

          bounds(node.body.first.location)
          on_bodystmt(stmts, nil, nil, nil)
        when BeginNode
          visit_begin_node_clauses(location, node, allow_newline)
        else
          raise
        end
      end

      # foo(&bar)
      #     ^^^^
      def visit_block_argument_node(node)
        visit(node.expression)
      end

      # foo { |; bar| }
      #          ^^^
      def visit_block_local_variable_node(node)
        bounds(node.location)
        on_ident(node.name.to_s)
      end

      # Visit a BlockNode.
      def visit_block_node(node)
        braces = node.opening == "{"
        parameters = visit(node.parameters)

        body =
          case node.body
          when nil
            bounds(node.location)
            stmts = on_stmts_add(on_stmts_new, on_void_stmt)

            bounds(node.location)
            braces ? stmts : on_bodystmt(stmts, nil, nil, nil)
          when StatementsNode
            stmts = node.body.body
            stmts.unshift(nil) if void_stmt?(node.parameters&.location || node.opening_loc, node.body.location, false)
            stmts = visit_statements_node_body(stmts)

            bounds(node.body.location)
            braces ? stmts : on_bodystmt(stmts, nil, nil, nil)
          when BeginNode
            visit_body_node(node.parameters&.location || node.opening_loc, node.body)
          else
            raise
          end

        if braces
          bounds(node.location)
          on_brace_block(parameters, body)
        else
          bounds(node.location)
          on_do_block(parameters, body)
        end
      end

      # def foo(&bar); end
      #         ^^^^
      def visit_block_parameter_node(node)
        if node.name_loc.nil?
          bounds(node.location)
          on_blockarg(nil)
        else
          bounds(node.name_loc)
          name = visit_token(node.name.to_s)

          bounds(node.location)
          on_blockarg(name)
        end
      end

      # A block's parameters.
      def visit_block_parameters_node(node)
        parameters =
          if node.parameters.nil?
            on_params(nil, nil, nil, nil, nil, nil, nil)
          else
            visit(node.parameters)
          end

        locals =
          if node.locals.any?
            visit_all(node.locals)
          else
            visit_block_parameters_node_empty_locals
          end

        bounds(node.location)
        on_block_var(parameters, locals)
      end

      if RUBY_ENGINE == "jruby"
        # For JRuby, empty locals in an on_block_var is nil.
        private def visit_block_parameters_node_empty_locals; nil; end
      else
        # For everyone else, empty locals in an on_block_var is false.
        private def visit_block_parameters_node_empty_locals; false; end
      end

      # break
      # ^^^^^
      #
      # break foo
      # ^^^^^^^^^
      def visit_break_node(node)
        if node.arguments.nil?
          bounds(node.location)
          on_break(on_args_new)
        else
          arguments = visit(node.arguments)

          bounds(node.location)
          on_break(arguments)
        end
      end

      # foo
      # ^^^
      #
      # foo.bar
      # ^^^^^^^
      #
      # foo.bar() {}
      # ^^^^^^^^^^^^
      def visit_call_node(node)
        if node.call_operator_loc.nil?
          case node.name
          when :[]
            receiver = visit(node.receiver)
            arguments, block = visit_call_node_arguments(node.arguments, node.block, trailing_comma?(node.arguments&.location || node.location, node.closing_loc))

            bounds(node.location)
            call = on_aref(receiver, arguments)

            if block.nil?
              call
            else
              bounds(node.location)
              on_method_add_block(call, block)
            end
          when :[]=
            receiver = visit(node.receiver)

            *arguments, last_argument = node.arguments.arguments
            arguments << node.block if !node.block.nil?

            arguments =
              if arguments.any?
                args = visit_arguments(arguments)

                if !node.block.nil?
                  args
                else
                  bounds(arguments.first.location)
                  on_args_add_block(args, false)
                end
              end

            bounds(node.location)
            call = on_aref_field(receiver, arguments)
            value = visit_write_value(last_argument)

            bounds(last_argument.location)
            on_assign(call, value)
          when :-@, :+@, :~@
            receiver = visit(node.receiver)

            bounds(node.location)
            on_unary(node.name, receiver)
          when :!@
            receiver = visit(node.receiver)

            bounds(node.location)
            on_unary(node.message == "not" ? :not : :!@, receiver)
          when *BINARY_OPERATORS
            receiver = visit(node.receiver)
            value = visit(node.arguments.arguments.first)

            bounds(node.location)
            on_binary(receiver, node.name, value)
          else
            bounds(node.message_loc)
            message = visit_token(node.message, false)

            if node.variable_call?
              on_vcall(message)
            else
              arguments, block = visit_call_node_arguments(node.arguments, node.block, trailing_comma?(node.arguments&.location || node.location, node.closing_loc || node.location))
              call =
                if node.opening_loc.nil? && arguments&.any?
                  bounds(node.location)
                  on_command(message, arguments)
                elsif !node.opening_loc.nil?
                  bounds(node.location)
                  on_method_add_arg(on_fcall(message), on_arg_paren(arguments))
                else
                  bounds(node.location)
                  on_method_add_arg(on_fcall(message), on_args_new)
                end

              if block.nil?
                call
              else
                bounds(node.block.location)
                on_method_add_block(call, block)
              end
            end
          end
        else
          receiver = visit(node.receiver)

          bounds(node.call_operator_loc)
          call_operator = visit_token(node.call_operator)

          message =
            if node.message_loc.nil?
              :call
            else
              bounds(node.message_loc)
              visit_token(node.message, false)
            end

          if node.name.end_with?("=") && !node.message.end_with?("=") && !node.arguments.nil? && node.block.nil?
            value = visit_write_value(node.arguments.arguments.first)

            bounds(node.location)
            on_assign(on_field(receiver, call_operator, message), value)
          else
            arguments, block = visit_call_node_arguments(node.arguments, node.block, trailing_comma?(node.arguments&.location || node.location, node.closing_loc || node.location))
            call =
              if node.opening_loc.nil?
                bounds(node.location)

                if !arguments || arguments.empty?
                  on_call(receiver, call_operator, message)
                else
                  on_command_call(receiver, call_operator, message, arguments)
                end
              else
                bounds(node.opening_loc)
                arguments = on_arg_paren(arguments)

                bounds(node.location)
                on_method_add_arg(on_call(receiver, call_operator, message), arguments)
              end

            if block.nil?
              call
            else
              bounds(node.block.location)
              on_method_add_block(call, block)
            end
          end
        end
      end

      # Visit the arguments and block of a call node and return the arguments
      # and block as they should be used.
      private def visit_call_node_arguments(arguments_node, block_node, trailing_comma)
        arguments = arguments_node&.arguments || []
        block = block_node

        if block.is_a?(BlockArgumentNode)
          arguments << block
          block = nil
        end

        [
          if arguments.length == 1 && arguments.first.is_a?(ForwardingArgumentsNode)
            visit(arguments.first)
          elsif arguments.any?
            args = visit_arguments(arguments)

            if block_node.is_a?(BlockArgumentNode) || arguments.last.is_a?(ForwardingArgumentsNode) || command?(arguments.last) || trailing_comma
              args
            else
              bounds(arguments.first.location)
              on_args_add_block(args, false)
            end
          end,
          visit(block)
        ]
      end

      # Returns true if the given node is a command node.
      private def command?(node)
        node.is_a?(CallNode) &&
          node.opening_loc.nil? &&
          (!node.arguments.nil? || node.block.is_a?(BlockArgumentNode)) &&
          !BINARY_OPERATORS.include?(node.name)
      end

      # foo.bar += baz
      # ^^^^^^^^^^^^^^^
      def visit_call_operator_write_node(node)
        receiver = visit(node.receiver)

        bounds(node.call_operator_loc)
        call_operator = visit_token(node.call_operator)

        bounds(node.message_loc)
        message = visit_token(node.message)

        bounds(node.location)
        target = on_field(receiver, call_operator, message)

        bounds(node.operator_loc)
        operator = on_op("#{node.operator}=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # foo.bar &&= baz
      # ^^^^^^^^^^^^^^^
      def visit_call_and_write_node(node)
        receiver = visit(node.receiver)

        bounds(node.call_operator_loc)
        call_operator = visit_token(node.call_operator)

        bounds(node.message_loc)
        message = visit_token(node.message)

        bounds(node.location)
        target = on_field(receiver, call_operator, message)

        bounds(node.operator_loc)
        operator = on_op("&&=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # foo.bar ||= baz
      # ^^^^^^^^^^^^^^^
      def visit_call_or_write_node(node)
        receiver = visit(node.receiver)

        bounds(node.call_operator_loc)
        call_operator = visit_token(node.call_operator)

        bounds(node.message_loc)
        message = visit_token(node.message)

        bounds(node.location)
        target = on_field(receiver, call_operator, message)

        bounds(node.operator_loc)
        operator = on_op("||=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # foo.bar, = 1
      # ^^^^^^^
      def visit_call_target_node(node)
        if node.call_operator == "::"
          receiver = visit(node.receiver)

          bounds(node.message_loc)
          message = visit_token(node.message)

          bounds(node.location)
          on_const_path_field(receiver, message)
        else
          receiver = visit(node.receiver)

          bounds(node.call_operator_loc)
          call_operator = visit_token(node.call_operator)

          bounds(node.message_loc)
          message = visit_token(node.message)

          bounds(node.location)
          on_field(receiver, call_operator, message)
        end
      end

      # foo => bar => baz
      #        ^^^^^^^^^^
      def visit_capture_pattern_node(node)
        value = visit(node.value)
        target = visit(node.target)

        bounds(node.location)
        on_binary(value, :"=>", target)
      end

      # case foo; when bar; end
      # ^^^^^^^^^^^^^^^^^^^^^^^
      def visit_case_node(node)
        predicate = visit(node.predicate)
        clauses =
          node.conditions.reverse_each.inject(visit(node.consequent)) do |consequent, condition|
            on_when(*visit(condition), consequent)
          end

        bounds(node.location)
        on_case(predicate, clauses)
      end

      # case foo; in bar; end
      # ^^^^^^^^^^^^^^^^^^^^^
      def visit_case_match_node(node)
        predicate = visit(node.predicate)
        clauses =
          node.conditions.reverse_each.inject(visit(node.consequent)) do |consequent, condition|
            on_in(*visit(condition), consequent)
          end

        bounds(node.location)
        on_case(predicate, clauses)
      end

      # class Foo; end
      # ^^^^^^^^^^^^^^
      def visit_class_node(node)
        constant_path =
          if node.constant_path.is_a?(ConstantReadNode)
            bounds(node.constant_path.location)
            on_const_ref(on_const(node.constant_path.name.to_s))
          else
            visit(node.constant_path)
          end

        superclass = visit(node.superclass)
        bodystmt = visit_body_node(node.superclass&.location || node.constant_path.location, node.body, node.superclass.nil?)

        bounds(node.location)
        on_class(constant_path, superclass, bodystmt)
      end

      # @@foo
      # ^^^^^
      def visit_class_variable_read_node(node)
        bounds(node.location)
        on_var_ref(on_cvar(node.slice))
      end

      # @@foo = 1
      # ^^^^^^^^^
      #
      # @@foo, @@bar = 1
      # ^^^^^  ^^^^^
      def visit_class_variable_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_cvar(node.name.to_s))
        value = visit_write_value(node.value)

        bounds(node.location)
        on_assign(target, value)
      end

      # @@foo += bar
      # ^^^^^^^^^^^^
      def visit_class_variable_operator_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_cvar(node.name.to_s))

        bounds(node.operator_loc)
        operator = on_op("#{node.operator}=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # @@foo &&= bar
      # ^^^^^^^^^^^^^
      def visit_class_variable_and_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_cvar(node.name.to_s))

        bounds(node.operator_loc)
        operator = on_op("&&=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # @@foo ||= bar
      # ^^^^^^^^^^^^^
      def visit_class_variable_or_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_cvar(node.name.to_s))

        bounds(node.operator_loc)
        operator = on_op("||=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # @@foo, = bar
      # ^^^^^
      def visit_class_variable_target_node(node)
        bounds(node.location)
        on_var_field(on_cvar(node.name.to_s))
      end

      # Foo
      # ^^^
      def visit_constant_read_node(node)
        bounds(node.location)
        on_var_ref(on_const(node.name.to_s))
      end

      # Foo = 1
      # ^^^^^^^
      #
      # Foo, Bar = 1
      # ^^^  ^^^
      def visit_constant_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_const(node.name.to_s))
        value = visit_write_value(node.value)

        bounds(node.location)
        on_assign(target, value)
      end

      # Foo += bar
      # ^^^^^^^^^^^
      def visit_constant_operator_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_const(node.name.to_s))

        bounds(node.operator_loc)
        operator = on_op("#{node.operator}=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # Foo &&= bar
      # ^^^^^^^^^^^^
      def visit_constant_and_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_const(node.name.to_s))

        bounds(node.operator_loc)
        operator = on_op("&&=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # Foo ||= bar
      # ^^^^^^^^^^^^
      def visit_constant_or_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_const(node.name.to_s))

        bounds(node.operator_loc)
        operator = on_op("||=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # Foo, = bar
      # ^^^
      def visit_constant_target_node(node)
        bounds(node.location)
        on_var_field(on_const(node.name.to_s))
      end

      # Foo::Bar
      # ^^^^^^^^
      def visit_constant_path_node(node)
        if node.parent.nil?
          bounds(node.child.location)
          child = on_const(node.child.name.to_s)

          bounds(node.location)
          on_top_const_ref(child)
        else
          parent = visit(node.parent)

          bounds(node.child.location)
          child = on_const(node.child.name.to_s)

          bounds(node.location)
          on_const_path_ref(parent, child)
        end
      end

      # Foo::Bar = 1
      # ^^^^^^^^^^^^
      #
      # Foo::Foo, Bar::Bar = 1
      # ^^^^^^^^  ^^^^^^^^
      def visit_constant_path_write_node(node)
        target = visit_constant_path_write_node_target(node.target)
        value = visit_write_value(node.value)

        bounds(node.location)
        on_assign(target, value)
      end

      # Visit a constant path that is part of a write node.
      private def visit_constant_path_write_node_target(node)
        if node.parent.nil?
          bounds(node.child.location)
          child = on_const(node.child.name.to_s)

          bounds(node.location)
          on_top_const_field(child)
        else
          parent = visit(node.parent)

          bounds(node.child.location)
          child = on_const(node.child.name.to_s)

          bounds(node.location)
          on_const_path_field(parent, child)
        end
      end

      # Foo::Bar += baz
      # ^^^^^^^^^^^^^^^
      def visit_constant_path_operator_write_node(node)
        target = visit_constant_path_write_node_target(node.target)
        value = visit(node.value)

        bounds(node.operator_loc)
        operator = on_op("#{node.operator}=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # Foo::Bar &&= baz
      # ^^^^^^^^^^^^^^^^
      def visit_constant_path_and_write_node(node)
        target = visit_constant_path_write_node_target(node.target)
        value = visit(node.value)

        bounds(node.operator_loc)
        operator = on_op("&&=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # Foo::Bar ||= baz
      # ^^^^^^^^^^^^^^^^
      def visit_constant_path_or_write_node(node)
        target = visit_constant_path_write_node_target(node.target)
        value = visit(node.value)

        bounds(node.operator_loc)
        operator = on_op("||=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # Foo::Bar, = baz
      # ^^^^^^^^
      def visit_constant_path_target_node(node)
        visit_constant_path_write_node_target(node)
      end

      # def foo; end
      # ^^^^^^^^^^^^
      #
      # def self.foo; end
      # ^^^^^^^^^^^^^^^^^
      def visit_def_node(node)
        receiver = visit(node.receiver)
        operator =
          if !node.operator_loc.nil?
            bounds(node.operator_loc)
            visit_token(node.operator)
          end

        bounds(node.name_loc)
        name = visit_token(node.name_loc.slice)

        parameters =
          if node.parameters.nil?
            bounds(node.location)
            on_params(nil, nil, nil, nil, nil, nil, nil)
          else
            visit(node.parameters)
          end

        if !node.lparen_loc.nil?
          bounds(node.lparen_loc)
          parameters = on_paren(parameters)
        end

        bodystmt =
          if node.equal_loc.nil?
            visit_body_node(node.rparen_loc || node.end_keyword_loc, node.body)
          else
            body = visit(node.body.body.first)

            bounds(node.body.location)
            on_bodystmt(body, nil, nil, nil)
          end

        bounds(node.location)
        if receiver.nil?
          on_def(name, parameters, bodystmt)
        else
          on_defs(receiver, operator, name, parameters, bodystmt)
        end
      end

      # defined? a
      # ^^^^^^^^^^
      #
      # defined?(a)
      # ^^^^^^^^^^^
      def visit_defined_node(node)
        bounds(node.location)
        on_defined(visit(node.value))
      end

      # if foo then bar else baz end
      #                 ^^^^^^^^^^^^
      def visit_else_node(node)
        statements =
          if node.statements.nil?
            [nil]
          else
            body = node.statements.body
            body.unshift(nil) if void_stmt?(node.else_keyword_loc, node.statements.body[0].location, false)
            body
          end

        bounds(node.location)
        on_else(visit_statements_node_body(statements))
      end

      # "foo #{bar}"
      #      ^^^^^^
      def visit_embedded_statements_node(node)
        statements =
          if node.statements.nil?
            bounds(node.location)
            on_stmts_add(on_stmts_new, on_void_stmt)
          else
            visit(node.statements)
          end

        bounds(node.location)
        on_string_embexpr(statements)
      end

      # "foo #@bar"
      #      ^^^^^
      def visit_embedded_variable_node(node)
        variable = visit(node.variable)

        bounds(node.location)
        on_string_dvar(variable)
      end

      # Visit an EnsureNode node.
      def visit_ensure_node(node)
        statements =
          if node.statements.nil?
            [nil]
          else
            body = node.statements.body
            body.unshift(nil) if void_stmt?(node.ensure_keyword_loc, body[0].location, false)
            body
          end

        statements = visit_statements_node_body(statements)

        bounds(node.location)
        on_ensure(statements)
      end

      # false
      # ^^^^^
      def visit_false_node(node)
        bounds(node.location)
        on_var_ref(on_kw("false"))
      end

      # foo => [*, bar, *]
      #        ^^^^^^^^^^^
      def visit_find_pattern_node(node)
        constant = visit(node.constant)
        left =
          if node.left.expression.nil?
            bounds(node.left.location)
            on_var_field(nil)
          else
            visit(node.left.expression)
          end

        requireds = visit_all(node.requireds) if node.requireds.any?
        right =
          if node.right.expression.nil?
            bounds(node.right.location)
            on_var_field(nil)
          else
            visit(node.right.expression)
          end

        bounds(node.location)
        on_fndptn(constant, left, requireds, right)
      end

      # if foo .. bar; end
      #    ^^^^^^^^^^
      def visit_flip_flop_node(node)
        left = visit(node.left)
        right = visit(node.right)

        bounds(node.location)
        if node.exclude_end?
          on_dot3(left, right)
        else
          on_dot2(left, right)
        end
      end

      # 1.0
      # ^^^
      def visit_float_node(node)
        visit_number_node(node) { |text| on_float(text) }
      end

      # for foo in bar do end
      # ^^^^^^^^^^^^^^^^^^^^^
      def visit_for_node(node)
        index = visit(node.index)
        collection = visit(node.collection)
        statements =
          if node.statements.nil?
            bounds(node.location)
            on_stmts_add(on_stmts_new, on_void_stmt)
          else
            visit(node.statements)
          end

        bounds(node.location)
        on_for(index, collection, statements)
      end

      # def foo(...); bar(...); end
      #                   ^^^
      def visit_forwarding_arguments_node(node)
        bounds(node.location)
        on_args_forward
      end

      # def foo(...); end
      #         ^^^
      def visit_forwarding_parameter_node(node)
        bounds(node.location)
        on_args_forward
      end

      # super
      # ^^^^^
      #
      # super {}
      # ^^^^^^^^
      def visit_forwarding_super_node(node)
        if node.block.nil?
          bounds(node.location)
          on_zsuper
        else
          block = visit(node.block)

          bounds(node.location)
          on_method_add_block(on_zsuper, block)
        end
      end

      # $foo
      # ^^^^
      def visit_global_variable_read_node(node)
        bounds(node.location)
        on_var_ref(on_gvar(node.name.to_s))
      end

      # $foo = 1
      # ^^^^^^^^
      #
      # $foo, $bar = 1
      # ^^^^  ^^^^
      def visit_global_variable_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_gvar(node.name.to_s))
        value = visit_write_value(node.value)

        bounds(node.location)
        on_assign(target, value)
      end

      # $foo += bar
      # ^^^^^^^^^^^
      def visit_global_variable_operator_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_gvar(node.name.to_s))

        bounds(node.operator_loc)
        operator = on_op("#{node.operator}=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # $foo &&= bar
      # ^^^^^^^^^^^^
      def visit_global_variable_and_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_gvar(node.name.to_s))

        bounds(node.operator_loc)
        operator = on_op("&&=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # $foo ||= bar
      # ^^^^^^^^^^^^
      def visit_global_variable_or_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_gvar(node.name.to_s))

        bounds(node.operator_loc)
        operator = on_op("||=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # $foo, = bar
      # ^^^^
      def visit_global_variable_target_node(node)
        bounds(node.location)
        on_var_field(on_gvar(node.name.to_s))
      end

      # {}
      # ^^
      def visit_hash_node(node)
        elements =
          if node.elements.any?
            args = visit_all(node.elements)

            bounds(node.elements.first.location)
            on_assoclist_from_args(args)
          end

        bounds(node.location)
        on_hash(elements)
      end

      # foo => {}
      #        ^^
      def visit_hash_pattern_node(node)
        constant = visit(node.constant)
        elements =
          if node.elements.any? || !node.rest.nil?
            node.elements.map do |element|
              [
                if (key = element.key).opening_loc.nil?
                  visit(key)
                else
                  bounds(key.value_loc)
                  if (value = key.value).empty?
                    on_string_content
                  else
                    on_string_add(on_string_content, on_tstring_content(value))
                  end
                end,
                visit(element.value)
              ]
            end
          end

        rest =
          case node.rest
          when AssocSplatNode
            visit(node.rest.value)
          when NoKeywordsParameterNode
            bounds(node.rest.location)
            on_var_field(:nil)
          end

        bounds(node.location)
        on_hshptn(constant, elements, rest)
      end

      # if foo then bar end
      # ^^^^^^^^^^^^^^^^^^^
      #
      # bar if foo
      # ^^^^^^^^^^
      #
      # foo ? bar : baz
      # ^^^^^^^^^^^^^^^
      def visit_if_node(node)
        if node.then_keyword == "?"
          predicate = visit(node.predicate)
          truthy = visit(node.statements.body.first)
          falsy = visit(node.consequent.statements.body.first)

          bounds(node.location)
          on_ifop(predicate, truthy, falsy)
        elsif node.statements.nil? || (node.predicate.location.start_offset < node.statements.location.start_offset)
          predicate = visit(node.predicate)
          statements =
            if node.statements.nil?
              bounds(node.location)
              on_stmts_add(on_stmts_new, on_void_stmt)
            else
              visit(node.statements)
            end
          consequent = visit(node.consequent)

          bounds(node.location)
          on_if(predicate, statements, consequent)
        else
          statements = visit(node.statements.body.first)
          predicate = visit(node.predicate)

          bounds(node.location)
          on_if_mod(predicate, statements)
        end
      end

      # 1i
      # ^^
      def visit_imaginary_node(node)
        visit_number_node(node) { |text| on_imaginary(text) }
      end

      # { foo: }
      #   ^^^^
      def visit_implicit_node(node)
      end

      # foo { |bar,| }
      #           ^
      def visit_implicit_rest_node(node)
        bounds(node.location)
        on_excessed_comma
      end

      # case foo; in bar; end
      # ^^^^^^^^^^^^^^^^^^^^^
      def visit_in_node(node)
        # This is a special case where we're not going to call on_in directly
        # because we don't have access to the consequent. Instead, we'll return
        # the component parts and let the parent node handle it.
        pattern = visit(node.pattern)
        statements =
          if node.statements.nil?
            bounds(node.location)
            on_stmts_add(on_stmts_new, on_void_stmt)
          else
            visit(node.statements)
          end

        [pattern, statements]
      end

      # foo[bar] += baz
      # ^^^^^^^^^^^^^^^
      def visit_index_operator_write_node(node)
        receiver = visit(node.receiver)
        arguments, _ = visit_call_node_arguments(node.arguments, node.block, trailing_comma?(node.arguments&.location || node.location, node.closing_loc))

        bounds(node.location)
        target = on_aref_field(receiver, arguments)

        bounds(node.operator_loc)
        operator = on_op("#{node.operator}=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # foo[bar] &&= baz
      # ^^^^^^^^^^^^^^^^
      def visit_index_and_write_node(node)
        receiver = visit(node.receiver)
        arguments, _ = visit_call_node_arguments(node.arguments, node.block, trailing_comma?(node.arguments&.location || node.location, node.closing_loc))

        bounds(node.location)
        target = on_aref_field(receiver, arguments)

        bounds(node.operator_loc)
        operator = on_op("&&=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # foo[bar] ||= baz
      # ^^^^^^^^^^^^^^^^
      def visit_index_or_write_node(node)
        receiver = visit(node.receiver)
        arguments, _ = visit_call_node_arguments(node.arguments, node.block, trailing_comma?(node.arguments&.location || node.location, node.closing_loc))

        bounds(node.location)
        target = on_aref_field(receiver, arguments)

        bounds(node.operator_loc)
        operator = on_op("||=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # foo[bar], = 1
      # ^^^^^^^^
      def visit_index_target_node(node)
        receiver = visit(node.receiver)
        arguments, _ = visit_call_node_arguments(node.arguments, node.block, trailing_comma?(node.arguments&.location || node.location, node.closing_loc))

        bounds(node.location)
        on_aref_field(receiver, arguments)
      end

      # @foo
      # ^^^^
      def visit_instance_variable_read_node(node)
        bounds(node.location)
        on_var_ref(on_ivar(node.name.to_s))
      end

      # @foo = 1
      # ^^^^^^^^
      def visit_instance_variable_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_ivar(node.name.to_s))
        value = visit_write_value(node.value)

        bounds(node.location)
        on_assign(target, value)
      end

      # @foo += bar
      # ^^^^^^^^^^^
      def visit_instance_variable_operator_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_ivar(node.name.to_s))

        bounds(node.operator_loc)
        operator = on_op("#{node.operator}=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # @foo &&= bar
      # ^^^^^^^^^^^^
      def visit_instance_variable_and_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_ivar(node.name.to_s))

        bounds(node.operator_loc)
        operator = on_op("&&=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # @foo ||= bar
      # ^^^^^^^^^^^^
      def visit_instance_variable_or_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_ivar(node.name.to_s))

        bounds(node.operator_loc)
        operator = on_op("||=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # @foo, = bar
      # ^^^^
      def visit_instance_variable_target_node(node)
        bounds(node.location)
        on_var_field(on_ivar(node.name.to_s))
      end

      # 1
      # ^
      def visit_integer_node(node)
        visit_number_node(node) { |text| on_int(text) }
      end

      # if /foo #{bar}/ then end
      #    ^^^^^^^^^^^^
      def visit_interpolated_match_last_line_node(node)
        bounds(node.parts.first.location)
        parts =
          node.parts.inject(on_regexp_new) do |content, part|
            on_regexp_add(content, visit_string_content(part))
          end

        bounds(node.closing_loc)
        closing = on_regexp_end(node.closing)

        bounds(node.location)
        on_regexp_literal(parts, closing)
      end

      # /foo #{bar}/
      # ^^^^^^^^^^^^
      def visit_interpolated_regular_expression_node(node)
        bounds(node.parts.first.location)
        parts =
          node.parts.inject(on_regexp_new) do |content, part|
            on_regexp_add(content, visit_string_content(part))
          end

        bounds(node.closing_loc)
        closing = on_regexp_end(node.closing)

        bounds(node.location)
        on_regexp_literal(parts, closing)
      end

      # "foo #{bar}"
      # ^^^^^^^^^^^^
      def visit_interpolated_string_node(node)
        if node.opening&.start_with?("<<~")
          heredoc = visit_string_heredoc_node(node.parts)

          bounds(node.location)
          on_string_literal(heredoc)
        elsif !node.heredoc? && node.parts.length > 1 && node.parts.any? { |part| (part.is_a?(StringNode) || part.is_a?(InterpolatedStringNode)) && !part.opening_loc.nil? }
          first, *rest = node.parts
          rest.inject(visit(first)) do |content, part|
            concat = visit(part)

            bounds(part.location)
            on_string_concat(content, concat)
          end
        else
          bounds(node.parts.first.location)
          parts =
            node.parts.inject(on_string_content) do |content, part|
              on_string_add(content, visit_string_content(part))
            end

          bounds(node.location)
          on_string_literal(parts)
        end
      end

      # :"foo #{bar}"
      # ^^^^^^^^^^^^^
      def visit_interpolated_symbol_node(node)
        bounds(node.parts.first.location)
        parts =
          node.parts.inject(on_string_content) do |content, part|
            on_string_add(content, visit_string_content(part))
          end

        bounds(node.location)
        on_dyna_symbol(parts)
      end

      # `foo #{bar}`
      # ^^^^^^^^^^^^
      def visit_interpolated_x_string_node(node)
        if node.opening.start_with?("<<~")
          heredoc = visit_x_string_heredoc_node(node.parts)

          bounds(node.location)
          on_xstring_literal(heredoc)
        else
          bounds(node.parts.first.location)
          parts =
            node.parts.inject(on_xstring_new) do |content, part|
              on_xstring_add(content, visit_string_content(part))
            end

          bounds(node.location)
          on_xstring_literal(parts)
        end
      end

      # Visit an individual part of a string-like node.
      private def visit_string_content(part)
        if part.is_a?(StringNode)
          bounds(part.content_loc)
          on_tstring_content(part.content)
        else
          visit(part)
        end
      end

      # -> { it }
      # ^^^^^^^^^
      def visit_it_parameters_node(node)
      end

      # foo(bar: baz)
      #     ^^^^^^^^
      def visit_keyword_hash_node(node)
        elements = visit_all(node.elements)

        bounds(node.location)
        on_bare_assoc_hash(elements)
      end

      # def foo(**bar); end
      #         ^^^^^
      #
      # def foo(**); end
      #         ^^
      def visit_keyword_rest_parameter_node(node)
        if node.name_loc.nil?
          bounds(node.location)
          on_kwrest_param(nil)
        else
          bounds(node.name_loc)
          name = on_ident(node.name.to_s)

          bounds(node.location)
          on_kwrest_param(name)
        end
      end

      # -> {}
      def visit_lambda_node(node)
        parameters =
          if node.parameters.is_a?(BlockParametersNode)
            # Ripper does not track block-locals within lambdas, so we skip
            # directly to the parameters here.
            params =
              if node.parameters.parameters.nil?
                bounds(node.location)
                on_params(nil, nil, nil, nil, nil, nil, nil)
              else
                visit(node.parameters.parameters)
              end

            if node.parameters.opening_loc.nil?
              params
            else
              bounds(node.parameters.opening_loc)
              on_paren(params)
            end
          else
            bounds(node.location)
            on_params(nil, nil, nil, nil, nil, nil, nil)
          end

        braces = node.opening == "{"
        body =
          case node.body
          when nil
            bounds(node.location)
            stmts = on_stmts_add(on_stmts_new, on_void_stmt)

            bounds(node.location)
            braces ? stmts : on_bodystmt(stmts, nil, nil, nil)
          when StatementsNode
            stmts = node.body.body
            stmts.unshift(nil) if void_stmt?(node.parameters&.location || node.opening_loc, node.body.location, false)
            stmts = visit_statements_node_body(stmts)

            bounds(node.body.location)
            braces ? stmts : on_bodystmt(stmts, nil, nil, nil)
          when BeginNode
            visit_body_node(node.opening_loc, node.body)
          else
            raise
          end

        bounds(node.location)
        on_lambda(parameters, body)
      end

      # foo
      # ^^^
      def visit_local_variable_read_node(node)
        bounds(node.location)

        if node.name == :"0it"
          on_vcall(on_ident(node.slice))
        else
          on_var_ref(on_ident(node.slice))
        end
      end

      # foo = 1
      # ^^^^^^^
      def visit_local_variable_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_ident(node.name_loc.slice))
        value = visit_write_value(node.value)

        bounds(node.location)
        on_assign(target, value)
      end

      # foo += bar
      # ^^^^^^^^^^
      def visit_local_variable_operator_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_ident(node.name_loc.slice))

        bounds(node.operator_loc)
        operator = on_op("#{node.operator}=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # foo &&= bar
      # ^^^^^^^^^^^
      def visit_local_variable_and_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_ident(node.name_loc.slice))

        bounds(node.operator_loc)
        operator = on_op("&&=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # foo ||= bar
      # ^^^^^^^^^^^
      def visit_local_variable_or_write_node(node)
        bounds(node.name_loc)
        target = on_var_field(on_ident(node.name_loc.slice))

        bounds(node.operator_loc)
        operator = on_op("||=")
        value = visit_write_value(node.value)

        bounds(node.location)
        on_opassign(target, operator, value)
      end

      # foo, = bar
      # ^^^
      def visit_local_variable_target_node(node)
        bounds(node.location)
        on_var_field(on_ident(node.name.to_s))
      end

      # if /foo/ then end
      #    ^^^^^
      def visit_match_last_line_node(node)
        bounds(node.content_loc)
        tstring_content = on_tstring_content(node.content)

        bounds(node.closing_loc)
        closing = on_regexp_end(node.closing)

        on_regexp_literal(on_regexp_add(on_regexp_new, tstring_content), closing)
      end

      # foo in bar
      # ^^^^^^^^^^
      def visit_match_predicate_node(node)
        value = visit(node.value)
        pattern = on_in(visit(node.pattern), nil, nil)

        on_case(value, pattern)
      end

      # foo => bar
      # ^^^^^^^^^^
      def visit_match_required_node(node)
        value = visit(node.value)
        pattern = on_in(visit(node.pattern), nil, nil)

        on_case(value, pattern)
      end

      # /(?<foo>foo)/ =~ bar
      # ^^^^^^^^^^^^^^^^^^^^
      def visit_match_write_node(node)
        visit(node.call)
      end

      # A node that is missing from the syntax tree. This is only used in the
      # case of a syntax error.
      def visit_missing_node(node)
        raise "Cannot visit missing nodes directly."
      end

      # module Foo; end
      # ^^^^^^^^^^^^^^^
      def visit_module_node(node)
        constant_path =
          if node.constant_path.is_a?(ConstantReadNode)
            bounds(node.constant_path.location)
            on_const_ref(on_const(node.constant_path.name.to_s))
          else
            visit(node.constant_path)
          end

        bodystmt = visit_body_node(node.constant_path.location, node.body, true)

        bounds(node.location)
        on_module(constant_path, bodystmt)
      end

      # (foo, bar), bar = qux
      # ^^^^^^^^^^
      def visit_multi_target_node(node)
        bounds(node.location)
        targets = visit_multi_target_node_targets(node.lefts, node.rest, node.rights, true)

        if node.lparen_loc.nil?
          targets
        else
          bounds(node.lparen_loc)
          on_mlhs_paren(targets)
        end
      end

      # Visit the targets of a multi-target node.
      private def visit_multi_target_node_targets(lefts, rest, rights, skippable)
        if skippable && lefts.length == 1 && lefts.first.is_a?(MultiTargetNode) && rest.nil? && rights.empty?
          return visit(lefts.first)
        end

        mlhs = on_mlhs_new

        lefts.each do |left|
          bounds(left.location)
          mlhs = on_mlhs_add(mlhs, visit(left))
        end

        case rest
        when nil
          # do nothing
        when ImplicitRestNode
          # these do not get put into the generated tree
          bounds(rest.location)
          on_excessed_comma
        else
          bounds(rest.location)
          mlhs = on_mlhs_add_star(mlhs, visit(rest))
        end

        if rights.any?
          bounds(rights.first.location)
          post = on_mlhs_new

          rights.each do |right|
            bounds(right.location)
            post = on_mlhs_add(post, visit(right))
          end

          mlhs = on_mlhs_add_post(mlhs, post)
        end

        mlhs
      end

      # foo, bar = baz
      # ^^^^^^^^^^^^^^
      def visit_multi_write_node(node)
        bounds(node.location)
        targets = visit_multi_target_node_targets(node.lefts, node.rest, node.rights, true)

        unless node.lparen_loc.nil?
          bounds(node.lparen_loc)
          targets = on_mlhs_paren(targets)
        end

        value = visit_write_value(node.value)

        bounds(node.location)
        on_massign(targets, value)
      end

      # next
      # ^^^^
      #
      # next foo
      # ^^^^^^^^
      def visit_next_node(node)
        if node.arguments.nil?
          bounds(node.location)
          on_next(on_args_new)
        else
          arguments = visit(node.arguments)

          bounds(node.location)
          on_next(arguments)
        end
      end

      # nil
      # ^^^
      def visit_nil_node(node)
        bounds(node.location)
        on_var_ref(on_kw("nil"))
      end

      # def foo(**nil); end
      #         ^^^^^
      def visit_no_keywords_parameter_node(node)
        :nil
      end

      # -> { _1 + _2 }
      # ^^^^^^^^^^^^^^
      def visit_numbered_parameters_node(node)
      end

      # $1
      # ^^
      def visit_numbered_reference_read_node(node)
        bounds(node.location)
        on_backref(node.slice)
      end

      # def foo(bar: baz); end
      #         ^^^^^^^^
      def visit_optional_keyword_parameter_node(node)
        bounds(node.name_loc)
        name = on_label("#{node.name}:")
        value = visit(node.value)

        [name, value]
      end

      # def foo(bar = 1); end
      #         ^^^^^^^
      def visit_optional_parameter_node(node)
        bounds(node.name_loc)
        name = visit_token(node.name.to_s)
        value = visit(node.value)

        [name, value]
      end

      # a or b
      # ^^^^^^
      def visit_or_node(node)
        left = visit(node.left)
        right = visit(node.right)

        bounds(node.location)
        on_binary(left, node.operator.to_sym, right)
      end

      # def foo(bar, *baz); end
      #         ^^^^^^^^^
      def visit_parameters_node(node)
        requireds = node.requireds.map { |required| required.is_a?(MultiTargetNode) ? visit_destructured_parameter_node(required) : visit(required) } if node.requireds.any?
        optionals = visit_all(node.optionals) if node.optionals.any?
        rest = visit(node.rest)
        posts = node.posts.map { |post| post.is_a?(MultiTargetNode) ? visit_destructured_parameter_node(post) : visit(post) } if node.posts.any?
        keywords = visit_all(node.keywords) if node.keywords.any?
        keyword_rest = visit(node.keyword_rest)
        block = visit(node.block)

        bounds(node.location)
        on_params(requireds, optionals, rest, posts, keywords, keyword_rest, block)
      end

      # Visit a destructured positional parameter node.
      private def visit_destructured_parameter_node(node)
        bounds(node.location)
        targets = visit_multi_target_node_targets(node.lefts, node.rest, node.rights, false)

        bounds(node.lparen_loc)
        on_mlhs_paren(targets)
      end

      # ()
      # ^^
      #
      # (1)
      # ^^^
      def visit_parentheses_node(node)
        body =
          if node.body.nil?
            on_stmts_add(on_stmts_new, on_void_stmt)
          else
            visit(node.body)
          end

        bounds(node.location)
        on_paren(body)
      end

      # foo => ^(bar)
      #        ^^^^^^
      def visit_pinned_expression_node(node)
        expression = visit(node.expression)

        bounds(node.location)
        on_begin(expression)
      end

      # foo = 1 and bar => ^foo
      #                    ^^^^
      def visit_pinned_variable_node(node)
        visit(node.variable)
      end

      # END {}
      # ^^^^^^
      def visit_post_execution_node(node)
        statements =
          if node.statements.nil?
            bounds(node.location)
            on_stmts_add(on_stmts_new, on_void_stmt)
          else
            visit(node.statements)
          end

        bounds(node.location)
        on_END(statements)
      end

      # BEGIN {}
      # ^^^^^^^^
      def visit_pre_execution_node(node)
        statements =
          if node.statements.nil?
            bounds(node.location)
            on_stmts_add(on_stmts_new, on_void_stmt)
          else
            visit(node.statements)
          end

        bounds(node.location)
        on_BEGIN(statements)
      end

      # The top-level program node.
      def visit_program_node(node)
        body = node.statements.body
        body << nil if body.empty?
        statements = visit_statements_node_body(body)

        bounds(node.location)
        on_program(statements)
      end

      # 0..5
      # ^^^^
      def visit_range_node(node)
        left = visit(node.left)
        right = visit(node.right)

        bounds(node.location)
        if node.exclude_end?
          on_dot3(left, right)
        else
          on_dot2(left, right)
        end
      end

      # 1r
      # ^^
      def visit_rational_node(node)
        visit_number_node(node) { |text| on_rational(text) }
      end

      # redo
      # ^^^^
      def visit_redo_node(node)
        bounds(node.location)
        on_redo
      end

      # /foo/
      # ^^^^^
      def visit_regular_expression_node(node)
        if node.content.empty?
          bounds(node.closing_loc)
          closing = on_regexp_end(node.closing)

          on_regexp_literal(on_regexp_new, closing)
        else
          bounds(node.content_loc)
          tstring_content = on_tstring_content(node.content)

          bounds(node.closing_loc)
          closing = on_regexp_end(node.closing)

          on_regexp_literal(on_regexp_add(on_regexp_new, tstring_content), closing)
        end
      end

      # def foo(bar:); end
      #         ^^^^
      def visit_required_keyword_parameter_node(node)
        bounds(node.name_loc)
        [on_label("#{node.name}:"), false]
      end

      # def foo(bar); end
      #         ^^^
      def visit_required_parameter_node(node)
        bounds(node.location)
        on_ident(node.name.to_s)
      end

      # foo rescue bar
      # ^^^^^^^^^^^^^^
      def visit_rescue_modifier_node(node)
        expression = visit_write_value(node.expression)
        rescue_expression = visit(node.rescue_expression)

        bounds(node.location)
        on_rescue_mod(expression, rescue_expression)
      end

      # begin; rescue; end
      #        ^^^^^^^
      def visit_rescue_node(node)
        exceptions =
          case node.exceptions.length
          when 0
            nil
          when 1
            [visit(node.exceptions.first)]
          else
            bounds(node.location)
            length = node.exceptions.length

            node.exceptions.each_with_index.inject(on_args_new) do |mrhs, (exception, index)|
              arg = visit(exception)
              bounds(exception.location)

              if index == length - 1
                on_mrhs_add(on_mrhs_new_from_args(mrhs), arg)
              else
                on_args_add(mrhs, arg)
              end
            end
          end

        reference = visit(node.reference)
        statements =
          if node.statements.nil?
            bounds(node.location)
            on_stmts_add(on_stmts_new, on_void_stmt)
          else
            visit(node.statements)
          end

        consequent = visit(node.consequent)

        bounds(node.location)
        on_rescue(exceptions, reference, statements, consequent)
      end

      # def foo(*bar); end
      #         ^^^^
      #
      # def foo(*); end
      #         ^
      def visit_rest_parameter_node(node)
        if node.name_loc.nil?
          bounds(node.location)
          on_rest_param(nil)
        else
          bounds(node.name_loc)
          on_rest_param(visit_token(node.name.to_s))
        end
      end

      # retry
      # ^^^^^
      def visit_retry_node(node)
        bounds(node.location)
        on_retry
      end

      # return
      # ^^^^^^
      #
      # return 1
      # ^^^^^^^^
      def visit_return_node(node)
        if node.arguments.nil?
          bounds(node.location)
          on_return0
        else
          arguments = visit(node.arguments)

          bounds(node.location)
          on_return(arguments)
        end
      end

      # self
      # ^^^^
      def visit_self_node(node)
        bounds(node.location)
        on_var_ref(on_kw("self"))
      end

      # class << self; end
      # ^^^^^^^^^^^^^^^^^^
      def visit_singleton_class_node(node)
        expression = visit(node.expression)
        bodystmt = visit_body_node(node.body&.location || node.end_keyword_loc, node.body)

        bounds(node.location)
        on_sclass(expression, bodystmt)
      end

      # __ENCODING__
      # ^^^^^^^^^^^^
      def visit_source_encoding_node(node)
        bounds(node.location)
        on_var_ref(on_kw("__ENCODING__"))
      end

      # __FILE__
      # ^^^^^^^^
      def visit_source_file_node(node)
        bounds(node.location)
        on_var_ref(on_kw("__FILE__"))
      end

      # __LINE__
      # ^^^^^^^^
      def visit_source_line_node(node)
        bounds(node.location)
        on_var_ref(on_kw("__LINE__")) 
      end

      # foo(*bar)
      #     ^^^^
      #
      # def foo((bar, *baz)); end
      #               ^^^^
      #
      # def foo(*); bar(*); end
      #                 ^
      def visit_splat_node(node)
        visit(node.expression)
      end

      # A list of statements.
      def visit_statements_node(node)
        bounds(node.location)
        visit_statements_node_body(node.body)
      end

      # Visit the list of statements of a statements node. We support nil
      # statements in the list. This would normally not be allowed by the
      # structure of the prism parse tree, but we manually add them here so that
      # we can mirror Ripper's void stmt.
      private def visit_statements_node_body(body)
        body.inject(on_stmts_new) do |stmts, stmt|
          on_stmts_add(stmts, stmt.nil? ? on_void_stmt : visit(stmt))
        end
      end

      # "foo"
      # ^^^^^
      def visit_string_node(node)
        if (content = node.content).empty?
          bounds(node.location)
          on_string_literal(on_string_content)
        elsif (opening = node.opening) == "?"
          bounds(node.location)
          on_CHAR("?#{node.content}")
        elsif opening.start_with?("<<~")
          heredoc = visit_string_heredoc_node([node])

          bounds(node.location)
          on_string_literal(heredoc)
        else
          bounds(node.content_loc)
          tstring_content = on_tstring_content(content)

          bounds(node.location)
          on_string_literal(on_string_add(on_string_content, tstring_content))
        end
      end

      # Ripper gives back the escaped string content but strips out the common
      # leading whitespace. Prism gives back the unescaped string content and a
      # location for the escaped string content. Unfortunately these don't work
      # well together, so we need to re-derive the common leading whitespace.
      private def heredoc_common_whitespace(parts)
        common_whitespace = nil
        dedent_next = true

        parts.each do |part|
          if part.is_a?(StringNode)
            if dedent_next
              common_whitespace = [
                common_whitespace || Float::INFINITY,
                part.content[/\A\s*/].each_char.inject(0) do |part_whitespace, char|
                  char == "\t" ? ((part_whitespace / 8 + 1) * 8) : (part_whitespace + 1)
                end
              ].min
            end

            dedent_next = true
          else
            dedent_next = false
          end
        end

        common_whitespace
      end

      # Take the content of a string and return the index of the first character
      # that is not trimmed out by eliminating common whitespace.
      private def heredoc_trimmed_whitespace(content, common_whitespace)
        trimmed_whitespace = 0

        index = 0
        while index < content.length && content[index].match?(/\s/) && trimmed_whitespace < common_whitespace
          if content[index] == "\t"
            trimmed_whitespace = ((trimmed_whitespace / 8 + 1) * 8)
            break if trimmed_whitespace > common_whitespace
          else
            trimmed_whitespace += 1
          end

          index += 1
        end

        index
      end

      # Visit a string that is expressed using a <<~ heredoc.
      private def visit_string_heredoc_node(parts)
        common_whitespace = heredoc_common_whitespace(parts)

        bounds(parts.first.location)
        parts.inject(on_string_content) do |string_content, part|
          on_string_add(
            string_content,
            if part.is_a?(StringNode)
              content = part.content
              trimmed_whitespace = heredoc_trimmed_whitespace(content, common_whitespace)

              bounds(part.content_loc.copy(start_offset: part.content_loc.start_offset + trimmed_whitespace))
              on_tstring_content(part.content[trimmed_whitespace..])
            else
              visit(part)
            end
          )
        end
      end

      # Visit an xstring that is expressed using a <<~ heredoc.
      private def visit_x_string_heredoc_node(parts)
        common_whitespace = heredoc_common_whitespace(parts)

        bounds(parts.first.location)
        parts.inject(on_xstring_new) do |xstring, part|
          on_xstring_add(
            xstring,
            if part.is_a?(StringNode)
              content = part.content
              trimmed_whitespace = heredoc_trimmed_whitespace(content, common_whitespace)

              bounds(part.content_loc.copy(start_offset: part.content_loc.start_offset + trimmed_whitespace))
              on_tstring_content(part.content[trimmed_whitespace..])
            else
              visit(part)
            end
          )
        end
      end

      # super(foo)
      # ^^^^^^^^^^
      def visit_super_node(node)
        arguments, block = visit_call_node_arguments(node.arguments, node.block, trailing_comma?(node.arguments&.location || node.location, node.rparen_loc || node.location))

        if !node.lparen_loc.nil?
          bounds(node.lparen_loc)
          arguments = on_arg_paren(arguments)
        end

        bounds(node.location)
        call = on_super(arguments)

        if block.nil?
          call
        else
          bounds(node.block.location)
          on_method_add_block(call, block)
        end
      end

      # :foo
      # ^^^^
      def visit_symbol_node(node)
        if (opening = node.opening)&.match?(/^%s|['"]:?$/)
          bounds(node.value_loc)
          content = on_string_content

          if !(value = node.value).empty?
            content = on_string_add(content, on_tstring_content(value))
          end

          on_dyna_symbol(content)
        elsif (closing = node.closing) == ":"
          bounds(node.location)
          on_label("#{node.value}:")
        elsif opening.nil? && node.closing_loc.nil?
          bounds(node.value_loc)
          on_symbol_literal(visit_token(node.value))
        else
          bounds(node.value_loc)
          on_symbol_literal(on_symbol(visit_token(node.value)))
        end
      end

      # true
      # ^^^^
      def visit_true_node(node)
        bounds(node.location)
        on_var_ref(on_kw("true"))
      end

      # undef foo
      # ^^^^^^^^^
      def visit_undef_node(node)
        names = visit_all(node.names)

        bounds(node.location)
        on_undef(names)
      end

      # unless foo; bar end
      # ^^^^^^^^^^^^^^^^^^^
      #
      # bar unless foo
      # ^^^^^^^^^^^^^^
      def visit_unless_node(node)
        if node.statements.nil? || (node.predicate.location.start_offset < node.statements.location.start_offset)
          predicate = visit(node.predicate)
          statements =
            if node.statements.nil?
              bounds(node.location)
              on_stmts_add(on_stmts_new, on_void_stmt)
            else
              visit(node.statements)
            end
          consequent = visit(node.consequent)

          bounds(node.location)
          on_unless(predicate, statements, consequent)
        else
          statements = visit(node.statements.body.first)
          predicate = visit(node.predicate)

          bounds(node.location)
          on_unless_mod(predicate, statements)
        end
      end

      # until foo; bar end
      # ^^^^^^^^^^^^^^^^^
      #
      # bar until foo
      # ^^^^^^^^^^^^^
      def visit_until_node(node)
        if node.statements.nil? || (node.predicate.location.start_offset < node.statements.location.start_offset)
          predicate = visit(node.predicate)
          statements =
            if node.statements.nil?
              bounds(node.location)
              on_stmts_add(on_stmts_new, on_void_stmt)
            else
              visit(node.statements)
            end

          bounds(node.location)
          on_until(predicate, statements)
        else
          statements = visit(node.statements.body.first)
          predicate = visit(node.predicate)

          bounds(node.location)
          on_until_mod(predicate, statements)
        end
      end

      # case foo; when bar; end
      #           ^^^^^^^^^^^^^
      def visit_when_node(node)
        # This is a special case where we're not going to call on_when directly
        # because we don't have access to the consequent. Instead, we'll return
        # the component parts and let the parent node handle it.
        conditions = visit_arguments(node.conditions)
        statements =
          if node.statements.nil?
            bounds(node.location)
            on_stmts_add(on_stmts_new, on_void_stmt)
          else
            visit(node.statements)
          end

        [conditions, statements]
      end

      # while foo; bar end
      # ^^^^^^^^^^^^^^^^^^
      #
      # bar while foo
      # ^^^^^^^^^^^^^
      def visit_while_node(node)
        if node.statements.nil? || (node.predicate.location.start_offset < node.statements.location.start_offset)
          predicate = visit(node.predicate)
          statements =
            if node.statements.nil?
              bounds(node.location)
              on_stmts_add(on_stmts_new, on_void_stmt)
            else
              visit(node.statements)
            end

          bounds(node.location)
          on_while(predicate, statements)
        else
          statements = visit(node.statements.body.first)
          predicate = visit(node.predicate)

          bounds(node.location)
          on_while_mod(predicate, statements)
        end
      end

      # `foo`
      # ^^^^^
      def visit_x_string_node(node)
        if node.unescaped.empty?
          bounds(node.location)
          on_xstring_literal(on_xstring_new)
        elsif node.opening.start_with?("<<~")
          heredoc = visit_x_string_heredoc_node([node])

          bounds(node.location)
          on_xstring_literal(heredoc)
        else
          bounds(node.content_loc)
          content = on_tstring_content(node.content)

          bounds(node.location)
          on_xstring_literal(on_xstring_add(on_xstring_new, content))
        end
      end

      # yield
      # ^^^^^
      #
      # yield 1
      # ^^^^^^^
      def visit_yield_node(node)
        if node.arguments.nil? && node.lparen_loc.nil?
          bounds(node.location)
          on_yield0
        else
          arguments =
            if node.arguments.nil?
              bounds(node.location)
              on_args_new
            else
              visit(node.arguments)
            end

          unless node.lparen_loc.nil?
            bounds(node.lparen_loc)
            arguments = on_paren(arguments)
          end

          bounds(node.location)
          on_yield(arguments)
        end
      end

      private

      # Lazily initialize the parse result.
      def result
        @result ||= Prism.parse(source)
      end

      ##########################################################################
      # Helpers
      ##########################################################################

      # Returns true if there is a comma between the two locations.
      def trailing_comma?(left, right)
        source.byteslice(left.end_offset...right.start_offset).include?(",")
      end

      # Returns true if there is a semicolon between the two locations.
      def void_stmt?(left, right, allow_newline)
        pattern = allow_newline ? /[;#\n]/ : /[;#]/
        source.byteslice(left.end_offset...right.start_offset).match?(pattern)
      end

      # Visit the string content of a particular node. This method is used to
      # split into the various token types.
      def visit_token(token, allow_keywords = true)
        case token
        when "."
          on_period(token)
        when "`"
          on_backtick(token)
        when *(allow_keywords ? KEYWORDS : [])
          on_kw(token)
        when /^_/
          on_ident(token)
        when /^[[:upper:]]\w*$/
          on_const(token)
        when /^@@/
          on_cvar(token)
        when /^@/
          on_ivar(token)
        when /^\$/
          on_gvar(token)
        when /^[[:punct:]]/
          on_op(token)
        else
          on_ident(token)
        end
      end

      # Visit a node that represents a number. We need to explicitly handle the
      # unary - operator.
      def visit_number_node(node)
        slice = node.slice
        location = node.location

        if slice[0] == "-"
          bounds(location.copy(start_offset: location.start_offset + 1))
          value = yield slice[1..-1]

          bounds(node.location)
          on_unary(:-@, value)
        else
          bounds(location)
          yield slice
        end
      end

      # Visit a node that represents a write value. This is used to handle the
      # special case of an implicit array that is generated without brackets.
      def visit_write_value(node)
        if node.is_a?(ArrayNode) && node.opening_loc.nil?
          elements = node.elements
          length = elements.length

          bounds(elements.first.location)
          elements.each_with_index.inject((elements.first.is_a?(SplatNode) && length == 1) ? on_mrhs_new : on_args_new) do |args, (element, index)|
            arg = visit(element)
            bounds(element.location)

            if index == length - 1
              if element.is_a?(SplatNode)
                mrhs = index == 0 ? args : on_mrhs_new_from_args(args)
                on_mrhs_add_star(mrhs, arg)
              else
                on_mrhs_add(on_mrhs_new_from_args(args), arg)
              end
            else
              case element
              when BlockArgumentNode
                on_args_add_block(args, arg)
              when SplatNode
                on_args_add_star(args, arg)
              else
                on_args_add(args, arg)
              end
            end
          end
        else
          visit(node)
        end
      end

      # This method is responsible for updating lineno and column information
      # to reflect the current node.
      #
      # This method could be drastically improved with some caching on the start
      # of every line, but for now it's good enough.
      def bounds(location)
        @lineno = location.start_line
        @column = location.start_column
      end

      ##########################################################################
      # Ripper interface
      ##########################################################################

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
