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

      # In an alias statement Ripper will emit @kw instead of @ident if the
      # object being aliased is a Ruby keyword. For instance, in the line
      # "alias :foo :if", the :if is treated as a lexer keyword. So we need to
      # know what symbols are also keywords.
      RUBY_KEYWORDS = [
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

      private_constant :RUBY_KEYWORDS

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
        new_name = visit_alias_method_node_value(node.new_name)
        old_name = visit_alias_method_node_value(node.old_name)

        bounds(node.location)
        on_alias(new_name, old_name)
      end

      # Visit one side of an alias method node.
      private def visit_alias_method_node_value(node)
        if node.is_a?(SymbolNode) && node.opening_loc.nil?
          visit_symbol_literal_node(node, no_symbol_wrapper: true)
        else
          visit(node)
        end
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
        elements = visit_arguments(node.elements) unless node.elements.empty?

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
          if !node.rest.nil?
            if !node.rest.expression.nil?
              visit(node.rest.expression)
            else
              bounds(node.rest.location)
              on_var_field(nil)
            end
          end
        posts = visit_all(node.posts) if node.posts.any?

        bounds(node.location)
        on_aryptn(constant, requireds, rest, posts)
      end

      # foo(bar)
      #     ^^^
      def visit_arguments_node(node)
        bounds(node.location)
        on_args_add_block(visit_arguments(node.arguments), false)
      end

      # { a: 1 }
      #   ^^^^
      def visit_assoc_node(node)
        key =
          if node.key.is_a?(SymbolNode) && node.operator_loc.nil?
            bounds(node.key.location)
            on_label(node.key.slice)
          else
            visit(node.key)
          end

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
        clauses = visit_begin_node_clauses(node)

        bounds(node.location)
        on_begin(clauses)
      end

      # Visit the clauses of a begin node to form an on_bodystmt call.
      private def visit_begin_node_clauses(node)
        statements =
          if node.statements.nil?
            on_stmts_add(on_stmts_new, on_void_stmt)
          else
            body = node.statements.body
            body.unshift(nil) if source.byteslice(node.begin_keyword_loc.end_offset...node.statements.body[0].location.start_offset).include?(";")

            bounds(node.statements.location)
            visit_statements_node_body(body)
          end

        rescue_clause = visit(node.rescue_clause)
        else_clause = visit(node.else_clause)
        ensure_clause = visit(node.ensure_clause)

        bounds(node.location)
        on_bodystmt(statements, rescue_clause, else_clause, ensure_clause)
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
        params_val = node.parameters.nil? ? nil : visit(node.parameters)

        # If the body is empty, we use a void statement. If there is
        # a semicolon after the opening delimiter, we append a void
        # statement, unless the body is also empty. So we should never
        # get a double void statement.

        body_val = if node.body.nil?
          on_stmts_add(on_stmts_new, on_void_stmt)
        elsif node_has_semicolon?(node)
          v = visit(node.body)
          raise(NoMethodError, __method__, "Unexpected statement structure #{v.inspect}") if v[0] != :stmts_add
          v[1] = on_stmts_add(on_stmts_new, on_void_stmt)
          v
        else
          visit(node.body)
        end

        case node.opening
        when "{"
          on_brace_block(params_val, body_val)
        when "do"
          on_do_block(params_val, on_bodystmt(body_val, nil, nil, nil))
        else
          raise
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
          arguments = visit_arguments(node.arguments.arguments)

          bounds(node.location)
          on_break(on_args_add_block(arguments, false))
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
            arguments, block = visit_call_node_arguments(node.arguments, node.block)

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

            value = visit(last_argument)
            bounds(last_argument.location)
            on_assign(call, value)
          when :-@, :+@, :~@
            receiver = visit(node.receiver)

            bounds(node.location)
            on_unary(node.name, receiver)
          when :!@
            if node.message == "not"
              receiver =
                case node.receiver
                when nil
                  nil
                when ParenthesesNode
                  body = visit(node.receiver.body&.body&.first) || false

                  bounds(node.receiver.location)
                  on_paren(body)
                else
                  visit(node.receiver)
                end

              bounds(node.location)
              on_unary(:not, receiver)
            else
              receiver = visit(node.receiver)

              bounds(node.location)
              on_unary(:!@, receiver)
            end
          when :!=, :!~, :=~, :==, :===, :<=>, :>, :>=, :<, :<=, :&, :|, :^, :>>, :<<, :-, :+, :%, :/, :*, :**
            receiver = visit(node.receiver)
            value = visit(node.arguments.arguments.first)

            bounds(node.location)
            on_binary(receiver, node.name, value)
          else
            bounds(node.message_loc)
            message = on_ident(node.message)

            if node.variable_call?
              on_vcall(message)
            else
              arguments, block = visit_call_node_arguments(node.arguments, node.block)
              call =
                if node.opening_loc.nil? && (arguments&.any? || block.nil?)
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

          bounds(node.message_loc)
          message = visit_token(node.message)

          if node.name.end_with?("=") && !node.message.end_with?("=") && !node.arguments.nil? && node.block.nil?
            bounds(node.arguments.location)
            value = visit(node.arguments.arguments.first)

            bounds(node.location)
            on_assign(on_field(receiver, call_operator, message), value)
          else
            arguments, block = visit_call_node_arguments(node.arguments, node.block)
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
      private def visit_call_node_arguments(arguments_node, block_node)
        arguments = arguments_node&.arguments || []
        block = block_node

        if block.is_a?(BlockArgumentNode)
          arguments << block
          block = nil
        end

        arguments =
          if arguments.any?
            args = visit_arguments(arguments)

            if block.is_a?(BlockArgumentNode)
              args
            else
              bounds(arguments.first.location)
              on_args_add_block(args, false)
            end
          end

        block = visit(block) if !block.nil?
        [arguments, block]
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

        value = visit(node.value)
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

        value = visit(node.value)
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

        value = visit(node.value)
        on_opassign(target, operator, value)
      end

      # foo.bar, = 1
      # ^^^^^^^
      def visit_call_target_node(node)
        receiver = visit(node.receiver)

        bounds(node.call_operator_loc)
        call_operator = visit_token(node.call_operator)

        bounds(node.message_loc)
        message = visit_token(node.message)

        bounds(node.location)
        on_field(receiver, call_operator, message)
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
          node.conditions.reverse_each.inject(nil) do |consequent, condition|
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
          node.conditions.reverse_each.inject(nil) do |consequent, condition|
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
        bodystmt =
          case node.body
          when nil
            bounds(node.location)
            on_bodystmt(visit_statements_node_body([nil]), nil, nil, nil)
          when StatementsNode
            body = visit(node.body)

            bounds(node.body.location)
            on_bodystmt(body, nil, nil, nil)
          when BeginNode
            visit_begin_node_clauses(node.body)
          else
            raise
          end

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
        value = visit(node.value)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
            case node.body
            when nil
              bounds(node.location)
              on_bodystmt(visit_statements_node_body([nil]), nil, nil, nil)
            when StatementsNode
              body = visit(node.body)

              bounds(node.body.location)
              on_bodystmt(body, nil, nil, nil)
            when BeginNode
              visit_begin_node_clauses(node.body)
            else
              raise
            end
          else
            body = visit(node.body.body.first)

            bounds(node.body.location)
            on_bodystmt(body, nil, nil, nil)
          end

        on_def(name, parameters, bodystmt)
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
            body.unshift(nil) if source.byteslice(node.else_keyword_loc.end_offset...node.statements.body[0].location.start_offset).include?(";")
          end

        bounds(node.location)
        on_else(visit_statements_node_body(statements))
      end

      # "foo #{bar}"
      #      ^^^^^^
      def visit_embedded_statements_node(node)
        statements = visit(node.statements)

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
        if node.statements
          # If there are any statements, we need to see if there's a semicolon
          # between the ensure and the start of the first statement.

          stmts_val = visit(node.statements)
          if node_has_semicolon?(node)
            # If there's a semicolon, we need to replace [:stmts_new] with
            # [:stmts_add, [:stmts_new], [:void_stmt]].
            stmts_val[1] = on_stmts_add(on_stmts_new, on_void_stmt)
          end
        else
          stmts_val = on_stmts_add(on_stmts_new, on_void_stmt)
        end
        on_ensure(stmts_val)
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
        raise NoMethodError, __method__
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
        value = visit(node.value)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
              bounds(element.key.location)
              key = on_label(element.key.slice)
              value = visit(element.value)

              [key, value]
            end
          end

        rest =
          if !node.rest.nil?
            visit(node.rest.value)
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
        arguments = visit(node.arguments)

        bounds(node.location)
        target = on_aref_field(receiver, arguments)

        bounds(node.operator_loc)
        operator = on_op("#{node.operator}=")

        value = visit(node.value)
        on_opassign(target, operator, value)
      end

      # foo[bar] &&= baz
      # ^^^^^^^^^^^^^^^^
      def visit_index_and_write_node(node)
        receiver = visit(node.receiver)
        arguments = visit(node.arguments)

        bounds(node.location)
        target = on_aref_field(receiver, arguments)

        bounds(node.operator_loc)
        operator = on_op("&&=")

        value = visit(node.value)
        on_opassign(target, operator, value)
      end

      # foo[bar] ||= baz
      # ^^^^^^^^^^^^^^^^
      def visit_index_or_write_node(node)
        receiver = visit(node.receiver)
        arguments = visit(node.arguments)

        bounds(node.location)
        target = on_aref_field(receiver, arguments)

        bounds(node.operator_loc)
        operator = on_op("||=")

        value = visit(node.value)
        on_opassign(target, operator, value)
      end

      # foo[bar], = 1
      # ^^^^^^^^
      def visit_index_target_node(node)
        receiver = visit(node.receiver)
        arguments = visit(node.arguments)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
        bounds(node.parts.first.location)
        parts =
          node.parts.inject(on_string_content) do |content, part|
            on_string_add(content, visit_string_content(part))
          end

        bounds(node.location)
        on_string_literal(parts)
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
        bounds(node.parts.first.location)
        parts =
          node.parts.inject(on_xstring_new) do |content, part|
            on_xstring_add(content, visit_string_content(part))
          end

        bounds(node.location)
        on_xstring_literal(parts)
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
          if node.parameters.nil?
            bounds(node.location)
            on_params(nil, nil, nil, nil, nil, nil, nil)
          else
            # Ripper does not track block-locals within lambdas, so we skip
            # directly to the parameters here.
            visit(node.parameters.parameters)
          end

        if !node.opening_loc.nil?
          bounds(node.opening_loc)
          parameters = on_paren(parameters)
        end

        body =
          if node.body.nil?
            bounds(node.location)
            on_stmts_add(on_stmts_new, on_void_stmt)
          else
            visit(node.body)
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
        value = visit(node.value)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
        value = visit(node.value)

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
        content = on_tstring_content(node.unescaped)

        bounds(node.closing_loc)
        closing = on_regexp_end(node.closing)

        on_regexp_literal(on_regexp_add(on_regexp_new, content), closing)
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
        raise NoMethodError, __method__
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

        bodystmt =
          case node.body
          when nil
            bounds(node.location)
            on_bodystmt(visit_statements_node_body([nil]), nil, nil, nil)
          when StatementsNode
            body = visit(node.body)

            bounds(node.body.location)
            on_bodystmt(body, nil, nil, nil)
          when BeginNode
            visit_begin_node_clauses(node.body)
          else
            raise
          end

        bounds(node.location)
        on_module(constant_path, bodystmt)
      end

      # (foo, bar), bar = qux
      # ^^^^^^^^^^
      def visit_multi_target_node(node)
        bounds(node.location)
        targets =
          [*node.lefts, *node.rest, *node.rights].inject(on_mlhs_new) do |mlhs, target|
            bounds(target.location)

            if target.is_a?(ImplicitRestNode)
              on_excessed_comma # these do not get put into the targets
              mlhs
            else
              on_mlhs_add(mlhs, visit(target))
            end
          end

        if node.lparen_loc.nil?
          targets
        else
          bounds(node.lparen_loc)
          on_mlhs_paren(targets)
        end
      end

      # foo, bar = baz
      # ^^^^^^^^^^^^^^
      def visit_multi_write_node(node)
        bounds(node.location)
        targets =
          [*node.lefts, *node.rest, *node.rights].inject(on_mlhs_new) do |mlhs, target|
            bounds(target.location)

            if target.is_a?(ImplicitRestNode)
              on_excessed_comma # these do not get put into the targets
              mlhs
            else
              on_mlhs_add(mlhs, visit(target))
            end
          end

        value = visit(node.value)

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
          arguments = visit_arguments(node.arguments.arguments)

          bounds(node.location)
          on_next(on_args_add_block(arguments, false))
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
        requireds = visit_all(node.requireds) if node.requireds.any?
        optionals = visit_all(node.optionals) if node.optionals.any?
        rest = visit(node.rest)
        posts = visit_all(node.posts) if node.posts.any?
        keywords = visit_all(node.keywords) if node.keywords.any?
        keyword_rest = visit(node.keyword_rest)
        block = node.keyword_rest.is_a?(ForwardingParameterNode) ? :& : visit(node.block)

        bounds(node.location)
        on_params(requireds, optionals, rest, posts, keywords, keyword_rest, block)
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
        statements = visit(node.statements)

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
        bounds(node.content_loc)
        content = on_tstring_content(node.unescaped)

        bounds(node.closing_loc)
        closing = on_regexp_end(node.closing)

        on_regexp_literal(on_regexp_add(on_regexp_new, content), closing)
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
        expression = visit(node.expression)
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
          on_return(on_args_add_block(arguments, false))
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
        bodystmt =
          case node.body
          when nil
            bounds(node.location)
            on_bodystmt(visit_statements_node_body([nil]), nil, nil, nil)
          when StatementsNode
            body = visit(node.body)

            bounds(node.body.location)
            on_bodystmt(body, nil, nil, nil)
          when BeginNode
            visit_begin_node_clauses(node.body)
          else
            raise
          end

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
        bounds(node.content_loc)
        unescaped = on_tstring_content(node.unescaped)

        bounds(node.location)
        on_string_literal(on_string_add(on_string_content, unescaped))
      end

      # super(foo)
      # ^^^^^^^^^^
      def visit_super_node(node)
        arguments = node.arguments&.arguments || []
        block = node.block

        if node.block.is_a?(BlockArgumentNode)
          arguments << block
          block = nil
        end

        arguments =
          if arguments.any?
            args = visit_arguments(arguments)

            if node.block.is_a?(BlockArgumentNode)
              args
            else
              bounds(arguments.first.location)
              on_args_add_block(args, false)
            end
          end

        if !node.lparen_loc.nil?
          bounds(node.lparen_loc)
          arguments = on_arg_paren(arguments)
        end

        if block.nil?
          bounds(node.location)
          on_super(arguments)
        else
          block = visit(block)

          bounds(node.location)
          on_method_add_block(on_super(arguments), block)
        end
      end

      # :foo
      # ^^^^
      def visit_symbol_node(node)
        if (opening = node.opening) && opening.match?(/^%s|['"]$/)
          bounds(node.value_loc)
          content = on_string_content

          if !(value = node.value).empty?
            content = on_string_add(content, on_tstring_content(value))
          end

          on_dyna_symbol(content)
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
        names =
          node.names.map do |name|
            case name
            when SymbolNode
              bounds(name.value_loc)
              token = visit_token(name.unescaped)

              if name.opening_loc.nil?
                on_symbol_literal(token)
              else
                on_symbol_literal(on_symbol(token))
              end
            when InterpolatedSymbolNode
              visit(name)
            else
              raise
            end
          end

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
        bounds(node.content_loc)
        unescaped = on_tstring_content(node.unescaped)

        bounds(node.location)
        on_xstring_literal(on_xstring_add(on_xstring_new, unescaped))
      end

      # yield
      # ^^^^^
      #
      # yield 1
      # ^^^^^^^
      def visit_yield_node(node)
        if node.arguments.nil?
          bounds(node.location)
          on_yield0
        else
          arguments = visit(node.arguments)

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

      # Visit the string content of a particular node. This method is used to
      # split into the various token types.
      def visit_token(token)
        case token
        when "."
          on_period(token)
        when *RUBY_KEYWORDS
          on_kw(token)
        when /^[[:upper:]]/
          on_const(token)
        when /^[[:punct:]]/
          on_op(token)
        else
          on_ident(token)
        end
      end

      # Ripper has several methods of emitting a symbol literal. Inside an alias
      # sometimes it suppresses the [:symbol] wrapper around ident. If the symbol
      # is also the name of a keyword (e.g. :if) it will emit a :@kw wrapper, not
      # an :@ident wrapper, with similar treatment for constants and operators.
      def visit_symbol_literal_node(node, no_symbol_wrapper: false)
        if (opening = node.opening) && (['"', "'"].include?(opening[-1]) || opening.start_with?("%s"))
          bounds(node.value_loc)
          str_val = node.value.to_s
          if str_val == ""
            return on_dyna_symbol(on_string_content)
          else
            tstring_val = on_tstring_content(str_val)
            return on_dyna_symbol(on_string_add(on_string_content, tstring_val))
          end
        end

        bounds(node.value_loc)
        node_name = node.value.to_s
        if RUBY_KEYWORDS.include?(node_name)
          token_val = on_kw(node_name)
        elsif node_name.length == 0
          raise NoMethodError, __method__
        elsif /[[:upper:]]/.match(node_name[0])
          token_val = on_const(node_name)
        elsif /[[:punct:]]/.match(node_name[0])
          token_val = on_op(node_name)
        else
          token_val = on_ident(node_name)
        end
        sym_val = no_symbol_wrapper ? token_val : on_symbol(token_val)
        on_symbol_literal(sym_val)
      end

      # Visit a node that represents a number. We need to explicitly handle the
      # unary - operator.
      def visit_number_node(node)
        slice = node.slice
        location = node.location

        if slice[0] == "-"
          bounds_values(location.start_line, location.start_column + 1)
          value = yield slice[1..-1]

          bounds(node.location)
          on_unary(visit_unary_operator(:-@), value)
        else
          bounds(location)
          yield slice
        end
      end

      if RUBY_ENGINE == "jruby" && Gem::Version.new(JRUBY_VERSION) < Gem::Version.new("9.4.6.0")
        # JRuby before 9.4.6.0 uses :- for unary minus instead of :-@
        def visit_unary_operator(value)
          value == :-@ ? :- : value
        end
      else
        # For most Rubies and JRuby after 9.4.6.0 this is a no-op.
        def visit_unary_operator(value)
          value
        end
      end

      # Some nodes, such as `begin`, `ensure` and `do` may have a semicolon
      # after the keyword and before the first statement. This affects
      # Ripper's return values.
      def node_has_semicolon?(node)
        first_field, second_field = case node
        when BeginNode
          [:begin_keyword_loc, :statements]
        when EnsureNode
          [:ensure_keyword_loc, :statements]
        when BlockNode
          [:opening_loc, :body]
        else
          raise NoMethodError, __method__
        end
        first_offs, second_offs = delimiter_offsets_for(node, first_field, second_field)

        # We need to know if there's a semicolon after the keyword, but before
        # the start of the first statement in the ensure.
        source.byteslice(first_offs..second_offs).include?(";")
      end

      # For a given node, grab the offsets for the end of the first field
      # and the beginning of the second field.
      def delimiter_offsets_for(node, first, second)
        first_field = node.send(first)
        first_end_loc = first_field.start_offset + first_field.length
        second_begin_loc = node.send(second).body[0].location.start_offset - 1
        [first_end_loc, second_begin_loc]
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

      # If we need to do something unusual, we can directly update the line number
      # and column to reflect the current node.
      def bounds_values(lineno, column)
        @lineno = lineno
        @column = column
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
