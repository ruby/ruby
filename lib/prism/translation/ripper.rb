# frozen_string_literal: true

require "ripper"

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
      # Visitor methods
      ############################################################################

      # Visit an ArrayNode node.
      def visit_array_node(node)
        elements = visit_elements(node.elements) unless node.elements.empty?
        bounds(node.location)
        on_array(elements)
      end

      # Visit a CallNode node.
      # Ripper distinguishes between many different method-call
      # nodes -- unary and binary operators, "command" calls with
      # no parentheses, and call/fcall/vcall.
      def visit_call_node(node)
        return visit_aref_node(node) if node.name == :[]
        return visit_aref_field_node(node) if node.name == :[]=

        if node.variable_call?
          raise NotImplementedError unless node.receiver.nil?

          bounds(node.message_loc)
          return on_vcall(on_ident(node.message))
        end

        if node.opening_loc.nil?
          return visit_no_paren_call(node)
        end

        # A non-operator method call with parentheses

        args = if node.arguments.nil?
          on_arg_paren(nil)
        else
          on_arg_paren(on_args_add_block(visit_elements(node.arguments.arguments), false))
        end

        bounds(node.message_loc)
        ident_val = on_ident(node.message)

        bounds(node.location)
        args_call_val = on_method_add_arg(on_fcall(ident_val), args)
        if node.block
          block_val = visit(node.block)

          return on_method_add_block(args_call_val, block_val)
        else
          return args_call_val
        end
      end

      # Visit a LocalVariableWriteNode.
      def visit_local_variable_write_node(node)
        bounds(node.name_loc)
        ident_val = on_ident(node.name.to_s)
        on_assign(on_var_field(ident_val), visit(node.value))
      end

      # Visit a LocalVariableAndWriteNode.
      def visit_local_variable_and_write_node(node)
        visit_binary_op_assign(node)
      end

      # Visit a LocalVariableOrWriteNode.
      def visit_local_variable_or_write_node(node)
        visit_binary_op_assign(node)
      end

      # Visit nodes for +=, *=, -=, etc., called LocalVariableOperatorWriteNodes.
      def visit_local_variable_operator_write_node(node)
        visit_binary_op_assign(node, operator: "#{node.operator}=")
      end

      # Visit a LocalVariableReadNode.
      def visit_local_variable_read_node(node)
        bounds(node.location)
        ident_val = on_ident(node.slice)

        on_var_ref(ident_val)
      end

      # Visit a BlockNode.
      def visit_block_node(node)
        params_val = node.parameters.nil? ? nil : visit(node.parameters)

        body_val = node.body.nil? ? on_stmts_add(on_stmts_new, on_void_stmt) : visit(node.body)

        on_brace_block(params_val, body_val)
      end

      # Visit a BlockParametersNode.
      def visit_block_parameters_node(node)
        on_block_var(visit(node.parameters), no_block_value)
      end

      # Visit a ParametersNode.
      # This will require expanding as we support more kinds of parameters.
      def visit_parameters_node(node)
        #on_params(required, optional, nil, nil, nil, nil, nil)
        on_params(visit_all(node.requireds), nil, nil, nil, nil, nil, nil)
      end

      # Visit a RequiredParameterNode.
      def visit_required_parameter_node(node)
        bounds(node.location)
        on_ident(node.name.to_s)
      end

      # Visit a BreakNode.
      def visit_break_node(node)
        return on_break(on_args_new) if node.arguments.nil?

        args_val = visit_elements(node.arguments.arguments)
        on_break(on_args_add_block(args_val, false))
      end

      # Visit an AliasMethodNode.
      def visit_alias_method_node(node)
        # For both the old and new name, if there is a colon in the symbol
        # name (e.g. 'alias :foo :bar') then we do *not* emit the [:symbol] wrapper around
        # the lexer token (e.g. :@ident) inside [:symbol_literal]. But if there
        # is no colon (e.g. 'alias foo bar') then we *do* still emit the [:symbol] wrapper.

        if node.new_name.is_a?(SymbolNode) && !node.new_name.opening
          new_name_val = visit_symbol_literal_node(node.new_name, no_symbol_wrapper: true)
        else
          new_name_val = visit(node.new_name)
        end
        if node.old_name.is_a?(SymbolNode) && !node.old_name.opening
          old_name_val = visit_symbol_literal_node(node.old_name, no_symbol_wrapper: true)
        else
          old_name_val = visit(node.old_name)
        end

        on_alias(new_name_val, old_name_val)
      end

      # Visit an AliasGlobalVariableNode.
      def visit_alias_global_variable_node(node)
        on_var_alias(visit(node.new_name), visit(node.old_name))
      end

      # Visit a GlobalVariableReadNode.
      def visit_global_variable_read_node(node)
        bounds(node.location)
        on_gvar(node.name.to_s)
      end

      # Visit a BackReferenceReadNode.
      def visit_back_reference_read_node(node)
        bounds(node.location)
        on_backref(node.name.to_s)
      end

      # Visit an AndNode.
      def visit_and_node(node)
        visit_binary_operator(node)
      end

      # Visit an OrNode.
      def visit_or_node(node)
        visit_binary_operator(node)
      end

      # Visit a TrueNode.
      def visit_true_node(node)
        bounds(node.location)
        on_var_ref(on_kw("true"))
      end

      # Visit a FalseNode.
      def visit_false_node(node)
        bounds(node.location)
        on_var_ref(on_kw("false"))
      end

      # Visit a FloatNode node.
      def visit_float_node(node)
        visit_number(node) { |text| on_float(text) }
      end

      # Visit a ImaginaryNode node.
      def visit_imaginary_node(node)
        visit_number(node) { |text| on_imaginary(text) }
      end

      # Visit an IntegerNode node.
      def visit_integer_node(node)
        visit_number(node) { |text| on_int(text) }
      end

      # Visit a ParenthesesNode node.
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

      # Visit a BeginNode node.
      # This is not at all bulletproof against different structures of begin/rescue/else/ensure/end.
      def visit_begin_node(node)
        rescue_val = node.rescue_clause ? on_rescue(nil, nil, visit(node.rescue_clause), nil) : nil
        ensure_val = node.ensure_clause ? on_ensure(visit(node.ensure_clause.statements)) : nil
        on_begin(on_bodystmt(visit(node.statements), rescue_val, nil, ensure_val))
      end

      # Visit a RescueNode node.
      def visit_rescue_node(node)
        visit(node.statements)
      end

      # Visit a ProgramNode node.
      def visit_program_node(node)
        statements = visit(node.statements)
        bounds(node.location)
        on_program(statements)
      end

      # Visit a RangeNode node.
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

      # Visit a RationalNode node.
      def visit_rational_node(node)
        visit_number(node) { |text| on_rational(text) }
      end

      # Visit a StringNode node.
      def visit_string_node(node)
        bounds(node.content_loc)
        tstring_val = on_tstring_content(node.unescaped.to_s)
        on_string_literal(on_string_add(on_string_content, tstring_val))
      end

      # Visit an XStringNode node.
      def visit_x_string_node(node)
        bounds(node.content_loc)
        tstring_val = on_tstring_content(node.unescaped.to_s)
        on_xstring_literal(on_xstring_add(on_xstring_new, tstring_val))
      end

      # Visit an InterpolatedStringNode node.
      def visit_interpolated_string_node(node)
        on_string_literal(visit_enumerated_node(node))
      end

      # Visit an EmbeddedStatementsNode node.
      def visit_embedded_statements_node(node)
        visit(node.statements)
      end

      # Visit a SymbolNode node.
      def visit_symbol_node(node)
        visit_symbol_literal_node(node)
      end

      # Visit an InterpolatedSymbolNode node.
      def visit_interpolated_symbol_node(node)
        on_dyna_symbol(visit_enumerated_node(node))
      end

      # Visit a StatementsNode node.
      def visit_statements_node(node)
        bounds(node.location)
        node.body.inject(on_stmts_new) do |stmts, stmt|
          on_stmts_add(stmts, visit(stmt))
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

      private

      # Generate Ripper events for a CallNode with no opening_loc
      def visit_no_paren_call(node)
        # No opening_loc can mean an operator. It can also mean a
        # method call with no parentheses.
        if node.message.match?(/^[[:punct:]]/)
          left = visit(node.receiver)
          if node.arguments&.arguments&.length == 1
            right = visit(node.arguments.arguments.first)

            return on_binary(left, node.name, right)
          elsif !node.arguments || node.arguments.empty?
            return on_unary(node.name, left)
          else
            raise NotImplementedError, "More than two arguments for operator"
          end
        elsif node.call_operator_loc.nil?
          # In Ripper a method call like "puts myvar" with no parentheses is a "command".
          bounds(node.message_loc)
          ident_val = on_ident(node.message)

          # Unless it has a block, and then it's an fcall (e.g. "foo { bar }")
          if node.block
            block_val = visit(node.block)
            # In these calls, even if node.arguments is nil, we still get an :args_new call.
            args = if node.arguments.nil?
              on_args_new
            else
              on_args_add_block(visit_elements(node.arguments.arguments))
            end
            method_args_val = on_method_add_arg(on_fcall(ident_val), args)
            return on_method_add_block(method_args_val, block_val)
          else
            if node.arguments.nil?
              return on_command(ident_val, nil)
            else
              args = on_args_add_block(visit_elements(node.arguments.arguments), false)
              return on_command(ident_val, args)
            end
          end
        else
          operator = node.call_operator_loc.slice
          if operator == "." || operator == "&."
            left_val = visit(node.receiver)

            bounds(node.call_operator_loc)
            operator_val = operator == "." ? on_period(node.call_operator) : on_op(node.call_operator)

            bounds(node.message_loc)
            right_val = on_ident(node.message)

            call_val = on_call(left_val, operator_val, right_val)

            if node.block
              block_val = visit(node.block)
              return on_method_add_block(call_val, block_val)
            else
              return call_val
            end
          else
            raise NotImplementedError, "operator other than . or &. for call: #{operator.inspect}"
          end
        end
      end

      # Visit a list of elements, like the elements of an array or arguments.
      def visit_elements(elements)
        bounds(elements.first.location)
        elements.inject(on_args_new) do |args, element|
          on_args_add(args, visit(element))
        end
      end

      # Visit an InterpolatedStringNode or an InterpolatedSymbolNode node.
      def visit_enumerated_node(node)
        parts = node.parts.map do |part|
          case part
          when StringNode
            bounds(part.content_loc)
            on_tstring_content(part.content)
          when EmbeddedStatementsNode
            on_string_embexpr(visit(part))
          else
            raise NotImplementedError, "Unexpected node type in visit_enumerated_node"
          end
        end

        parts.inject(on_string_content) do |items, item|
          on_string_add(items, item)
        end
      end

      # Visit an operation-and-assign node, such as +=.
      def visit_binary_op_assign(node, operator: node.operator)
        bounds(node.name_loc)
        ident_val = on_ident(node.name.to_s)

        bounds(node.operator_loc)
        op_val = on_op(operator)

        on_opassign(on_var_field(ident_val), op_val, visit(node.value))
      end

      # In Prism this is a CallNode with :[] as the operator.
      # In Ripper it's an :aref.
      def visit_aref_node(node)
        first_arg_val = visit(node.arguments.arguments[0])
        args_val = on_args_add_block(on_args_add(on_args_new, first_arg_val), false)
        on_aref(visit(node.receiver), args_val)
      end

      # In Prism this is a CallNode with :[]= as the operator.
      # In Ripper it's an :aref_field.
      def visit_aref_field_node(node)
        first_arg_val = visit(node.arguments.arguments[0])
        args_val = on_args_add_block(on_args_add(on_args_new, first_arg_val), false)
        assign_val = visit(node.arguments.arguments[1])
        on_assign(on_aref_field(visit(node.receiver), args_val), assign_val)
      end

      # In an alias statement Ripper will emit @kw instead of @ident if the object
      # being aliased is a Ruby keyword. For instance, in the line "alias :foo :if",
      # the :if is treated as a lexer keyword. So we need to know what symbols are
      # also keywords.
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
        "__LINE__",
      ]

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
          raise NotImplementedError
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
      def visit_number(node)
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

      if RUBY_ENGINE == "jruby"
        # For JRuby, "no block" in an on_block_var is nil
        def no_block_value
          nil
        end
      else
        # For CRuby et al, "no block" in an on_block_var is false
        def no_block_value
          false
        end
      end

      # Visit a binary operator node like an AndNode or OrNode
      def visit_binary_operator(node)
        left_val = visit(node.left)
        right_val = visit(node.right)
        on_binary(left_val, node.operator.to_sym, right_val)
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
