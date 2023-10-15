# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class ErrorsTest < TestCase
    include DSL

    def test_constant_path_with_invalid_token_after
      assert_error_messages "A::$b", [
        "Expected a constant after the `::` operator",
        "Expected a newline or semicolon after the statement"
      ]
    end

    def test_module_name_recoverable
      expected = ModuleNode(
        [],
        Location(),
        ConstantReadNode(:Parent),
        StatementsNode(
          [ModuleNode([], Location(), MissingNode(), nil, Location(), :"")]
        ),
        Location(),
        :Parent
      )

      assert_errors expected, "module Parent module end", [
        ["Expected a constant name after `module`", 20..20]
      ]
    end

    def test_for_loops_index_missing
      expected = ForNode(
        MissingNode(),
        expression("1..10"),
        StatementsNode([expression("i")]),
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "for in 1..10\ni\nend", [
        ["Expected an index after `for`", 0..3]
      ]
    end

    def test_for_loops_only_end
      expected = ForNode(
        MissingNode(),
        MissingNode(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "for end", [
        ["Expected an index after `for`", 0..3],
        ["Expected an `in` after the index in a `for` statement", 3..3],
        ["Expected a collection after the `in` in a `for` statement", 3..3]
      ]
    end

    def test_pre_execution_missing_brace
      expected = PreExecutionNode(
        StatementsNode([expression("1")]),
        Location(),
        Location(),
        Location()
      )

      assert_errors expected, "BEGIN 1 }", [
        ["Expected a `{` after `BEGIN`", 5..5]
      ]
    end

    def test_pre_execution_context
      expected = PreExecutionNode(
        StatementsNode([
          CallNode(
            expression("1"),
            nil,
            Location(),
            nil,
            ArgumentsNode([MissingNode()]),
            nil,
            nil,
            0,
            :+
          )
        ]),
        Location(),
        Location(),
        Location()
      )

      assert_errors expected, "BEGIN { 1 + }", [
        ["Expected an expression after the operator", 11..11]
      ]
    end

    def test_unterminated_embdoc
      assert_errors expression("1"), "1\n=begin\n", [
        ["Could not find a terminator for the embedded document", 2..9]
      ]
    end

    def test_unterminated_i_list
      assert_errors expression("%i["), "%i[", [
        ["Expected a closing delimiter for the `%i` list", 3..3]
      ]
    end

    def test_unterminated_w_list
      assert_errors expression("%w["), "%w[", [
        ["Expected a closing delimiter for the `%w` list", 3..3]
      ]
    end

    def test_unterminated_W_list
      assert_errors expression("%W["), "%W[", [
        ["Expected a closing delimiter for the `%W` list", 3..3]
      ]
    end

    def test_unterminated_regular_expression
      assert_errors expression("/hello"), "/hello", [
        ["Expected a closing delimiter for the regular expression", 1..1]
      ]
    end

    def test_unterminated_regular_expression_with_heredoc
      source = "<<-END + /b\nEND\n"

      assert_errors expression(source), source, [
        ["Expected a closing delimiter for the regular expression", 16..16]
      ]
    end

    def test_unterminated_xstring
      assert_errors expression("`hello"), "`hello", [
        ["Expected a closing delimiter for the `%x` or backtick string", 1..1]
      ]
    end

    def test_unterminated_string
      assert_errors expression('"hello'), '"hello', [
        ["Expected a closing delimiter for the interpolated string", 1..1]
      ]
    end

    def test_incomplete_instance_var_string
      assert_errors expression('%@#@@#'), '%@#@@#', [
        ["Incomplete instance variable", 4..5],
        ["Expected a newline or semicolon after the statement", 4..4]
      ]
    end

    def test_unterminated_s_symbol
      assert_errors expression("%s[abc"), "%s[abc", [
        ["Expected a closing delimiter for the dynamic symbol", 3..3]
      ]
    end

    def test_unterminated_parenthesized_expression
      assert_errors expression('(1 + 2'), '(1 + 2', [
        ["Expected a newline or semicolon after the statement", 6..6],
        ["Cannot parse the expression", 6..6],
        ["Expected a matching `)`", 6..6]
      ]
    end

    def test_missing_terminator_in_parentheses
      assert_error_messages "(0 0)", [
        "Expected a newline or semicolon after the statement"
      ]
    end

    def test_unterminated_argument_expression
      assert_errors expression('a %'), 'a %', [
        ["Invalid `%` token", 2..3],
        ["Expected an expression after the operator", 3..3],
      ]
    end

    def test_unterminated_interpolated_symbol
      assert_error_messages ":\"#", [
        "Expected a closing delimiter for the interpolated symbol"
      ]
    end

    def test_cr_without_lf_in_percent_expression
      assert_errors expression("%\r"), "%\r", [
        ["Invalid `%` token", 0..2],
      ]
    end

    def test_1_2_3
      assert_errors expression("(1, 2, 3)"), "(1, 2, 3)", [
        ["Expected a newline or semicolon after the statement", 2..2],
        ["Cannot parse the expression", 2..2],
        ["Expected a matching `)`", 2..2],
        ["Expected a newline or semicolon after the statement", 2..2],
        ["Cannot parse the expression", 2..2],
        ["Expected a newline or semicolon after the statement", 5..5],
        ["Cannot parse the expression", 5..5],
        ["Expected a newline or semicolon after the statement", 8..8],
        ["Cannot parse the expression", 8..8]
      ]
    end

    def test_return_1_2_3
      assert_error_messages "return(1, 2, 3)", [
        "Expected a newline or semicolon after the statement",
        "Cannot parse the expression",
        "Expected a matching `)`",
        "Expected a newline or semicolon after the statement",
        "Cannot parse the expression"
      ]
    end

    def test_return_1
      assert_errors expression("return 1,;"), "return 1,;", [
        ["Expected an argument", 9..9]
      ]
    end

    def test_next_1_2_3
      assert_errors expression("next(1, 2, 3)"), "next(1, 2, 3)", [
        ["Expected a newline or semicolon after the statement", 6..6],
        ["Cannot parse the expression", 6..6],
        ["Expected a matching `)`", 6..6],
        ["Expected a newline or semicolon after the statement", 12..12],
        ["Cannot parse the expression", 12..12]
      ]
    end

    def test_next_1
      assert_errors expression("next 1,;"), "next 1,;", [
        ["Expected an argument", 7..7]
      ]
    end

    def test_break_1_2_3
      assert_errors expression("break(1, 2, 3)"), "break(1, 2, 3)", [
        ["Expected a newline or semicolon after the statement", 7..7],
        ["Cannot parse the expression", 7..7],
        ["Expected a matching `)`", 7..7],
        ["Expected a newline or semicolon after the statement", 13..13],
        ["Cannot parse the expression", 13..13]
      ]
    end

    def test_break_1
      assert_errors expression("break 1,;"), "break 1,;", [
        ["Expected an argument", 8..8]
      ]
    end

    def test_argument_forwarding_when_parent_is_not_forwarding
      assert_errors expression('def a(x, y, z); b(...); end'), 'def a(x, y, z); b(...); end', [
        ["Unexpected `...` when the parent method is not forwarding", 18..21]
      ]
    end

    def test_argument_forwarding_only_effects_its_own_internals
      assert_errors expression('def a(...); b(...); end; def c(x, y, z); b(...); end'),
        'def a(...); b(...); end; def c(x, y, z); b(...); end', [
          ["Unexpected `...` when the parent method is not forwarding", 43..46]
        ]
    end

    def test_top_level_constant_with_downcased_identifier
      assert_error_messages "::foo", [
        "Expected a constant after the `::` operator",
        "Expected a newline or semicolon after the statement"
      ]
    end

    def test_top_level_constant_starting_with_downcased_identifier
      assert_error_messages "::foo::A", [
        "Expected a constant after the `::` operator",
        "Expected a newline or semicolon after the statement"
      ]
    end

    def test_aliasing_global_variable_with_non_global_variable
      assert_errors expression("alias $a b"), "alias $a b", [
        ["Invalid argument being passed to `alias`; expected a bare word, symbol, constant, or global variable", 9..10]
      ]
    end

    def test_aliasing_non_global_variable_with_global_variable
      assert_errors expression("alias a $b"), "alias a $b", [
        ["Invalid argument being passed to `alias`; expected a bare word, symbol, constant, or global variable", 8..10]
      ]
    end

    def test_aliasing_global_variable_with_global_number_variable
      assert_errors expression("alias $a $1"), "alias $a $1", [
        ["Invalid argument being passed to `alias`; expected a bare word, symbol, constant, or global variable", 9..11]
      ]
    end

    def test_def_with_expression_receiver_and_no_identifier
      assert_errors expression("def (a); end"), "def (a); end", [
        ["Expected a `.` or `::` after the receiver in a method definition", 7..7],
        ["Expected a method name", 7..7]
      ]
    end

    def test_def_with_multiple_statements_receiver
      assert_errors expression("def (\na\nb\n).c; end"), "def (\na\nb\n).c; end", [
        ["Expected a matching `)`", 7..7],
        ["Expected a `.` or `::` after the receiver in a method definition", 7..7],
        ["Expected a method name", 7..7],
        ["Cannot parse the expression", 10..10],
        ["Cannot parse the expression", 11..11]
      ]
    end

    def test_def_with_empty_expression_receiver
      assert_errors expression("def ().a; end"), "def ().a; end", [
        ["Expected a receiver for the method definition", 5..5]
      ]
    end

    def test_block_beginning_with_brace_and_ending_with_end
      assert_error_messages "x.each { x end", [
        "Expected a newline or semicolon after the statement",
        "Cannot parse the expression",
        "Cannot parse the expression",
        "Expected a block beginning with `{` to end with `}`"
      ]
    end

    def test_double_splat_followed_by_splat_argument
      expected = CallNode(
        nil,
        nil,
        Location(),
        Location(),
        ArgumentsNode([
          KeywordHashNode([AssocSplatNode(expression("kwargs"), Location())]),
          SplatNode(Location(), expression("args"))
        ]),
        Location(),
        nil,
        0,
        :a
      )

      assert_errors expected, "a(**kwargs, *args)", [
        ["Unexpected `*` splat argument after a `**` keyword splat argument", 12..17]
      ]
    end

    def test_arguments_after_block
      expected = CallNode(
        nil,
        nil,
        Location(),
        Location(),
        ArgumentsNode([expression("foo")]),
        Location(),
        BlockArgumentNode(expression("block"), Location()),
        0,
        :a
      )

      assert_errors expected, "a(&block, foo)", [
        ["Unexpected argument after a block argument", 10..13]
      ]
    end

    def test_arguments_binding_power_for_and
      assert_error_messages "foo(*bar and baz)", [
        "Expected a `)` to close the arguments",
        "Expected a newline or semicolon after the statement",
        "Cannot parse the expression"
      ]
    end

    def test_splat_argument_after_keyword_argument
      expected = CallNode(
        nil,
        nil,
        Location(),
        Location(),
        ArgumentsNode([
          KeywordHashNode(
            [AssocNode(
              SymbolNode(nil, Location(), Location(), "foo"),
              expression("bar"),
              nil
            )]
          ),
          SplatNode(Location(), expression("args"))
        ]),
        Location(),
        nil,
        0,
        :a
      )

      assert_errors expected, "a(foo: bar, *args)", [
        ["Unexpected `*` splat argument after a `**` keyword splat argument", 12..17]
      ]
    end

    def test_module_definition_in_method_body
      expected = DefNode(
        :foo,
        Location(),
        nil,
        nil,
        StatementsNode([ModuleNode([], Location(), ConstantReadNode(:A), nil, Location(), :A)]),
        [],
        Location(),
        nil,
        nil,
        nil,
        nil,
        Location()
      )

      assert_errors expected, "def foo;module A;end;end", [
        ["Unexpected module definition in a method body", 8..14]
      ]
    end

    def test_module_definition_in_method_body_within_block
      expected = DefNode(
        :foo,
        Location(),
        nil,
        nil,
        StatementsNode(
          [CallNode(
            nil,
            nil,
            Location(),
            nil,
            nil,
            nil,
            BlockNode(
              [],
              nil,
              StatementsNode([ModuleNode([], Location(), ConstantReadNode(:Foo), nil, Location(), :Foo)]),
              Location(),
              Location()
            ),
            0,
            :bar
          )]
        ),
        [],
        Location(),
        nil,
        nil,
        nil,
        nil,
        Location()
      )

      assert_errors expected, <<~RUBY, [["Unexpected module definition in a method body", 21..27]]
        def foo
          bar do
            module Foo;end
          end
        end
      RUBY
    end

    def test_class_definition_in_method_body
      expected = DefNode(
        :foo,
        Location(),
        nil,
        nil,
        StatementsNode(
          [ClassNode(
            [],
            Location(),
            ConstantReadNode(:A),
            nil,
            nil,
            nil,
            Location(),
            :A
          )]
        ),
        [],
        Location(),
        nil,
        nil,
        nil,
        nil,
        Location()
      )

      assert_errors expected, "def foo;class A;end;end", [
        ["Unexpected class definition in a method body", 8..13]
      ]
    end

    def test_bad_arguments
      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([
          RequiredParameterNode(:A),
          RequiredParameterNode(:@a),
          RequiredParameterNode(:$A),
          RequiredParameterNode(:@@a),
        ], [], nil, [], [], nil, nil),
        nil,
        [:A, :@a, :$A, :@@a],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(A, @a, $A, @@a);end", [
        ["Invalid formal argument; formal argument cannot be a constant", 8..9],
        ["Invalid formal argument; formal argument cannot be an instance variable", 11..13],
        ["Invalid formal argument; formal argument cannot be a global variable", 15..17],
        ["Invalid formal argument; formal argument cannot be a class variable", 19..22],
      ]
    end

    def test_cannot_assign_to_a_reserved_numbered_parameter
      expected = BeginNode(
        Location(),
        StatementsNode([
          LocalVariableWriteNode(:_1, 0, Location(), SymbolNode(Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_2, 0, Location(), SymbolNode(Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_3, 0, Location(), SymbolNode(Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_4, 0, Location(), SymbolNode(Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_5, 0, Location(), SymbolNode(Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_6, 0, Location(), SymbolNode(Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_7, 0, Location(), SymbolNode(Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_8, 0, Location(), SymbolNode(Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_9, 0, Location(), SymbolNode(Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_10, 0, Location(), SymbolNode(Location(), Location(), nil, "a"), Location())
        ]),
        nil,
        nil,
        nil,
        Location()
      )
      source = <<~RUBY
      begin
        _1=:a;_2=:a;_3=:a;_4=:a;_5=:a
        _6=:a;_7=:a;_8=:a;_9=:a;_10=:a
      end
      RUBY
      assert_errors expected, source, [
        ["Token reserved for a numbered parameter", 8..10],
        ["Token reserved for a numbered parameter", 14..16],
        ["Token reserved for a numbered parameter", 20..22],
        ["Token reserved for a numbered parameter", 26..28],
        ["Token reserved for a numbered parameter", 32..34],
        ["Token reserved for a numbered parameter", 40..42],
        ["Token reserved for a numbered parameter", 46..48],
        ["Token reserved for a numbered parameter", 52..54],
        ["Token reserved for a numbered parameter", 58..60],
      ]
    end

    def test_do_not_allow_trailing_commas_in_method_parameters
      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode(
          [RequiredParameterNode(:a), RequiredParameterNode(:b), RequiredParameterNode(:c)],
          [],
          nil,
          [],
          [],
          nil,
          nil
        ),
        nil,
        [:a, :b, :c],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(a,b,c,);end", [
        ["Unexpected `,` in parameters", 13..14]
      ]
    end

    def test_do_not_allow_trailing_commas_in_lambda_parameters
      expected = LambdaNode(
        [:a, :b],
        Location(),
        Location(),
        Location(),
        BlockParametersNode(
          ParametersNode([RequiredParameterNode(:a), RequiredParameterNode(:b)], [], nil, [], [], nil, nil),
          [],
          Location(),
          Location()
        ),
        nil
      )
      assert_errors expected, "-> (a, b, ) {}", [
        ["Unexpected `,` in parameters", 8..9]
      ]
    end

    def test_do_not_allow_multiple_codepoints_in_a_single_character_literal
      expected = StringNode(0, Location(), Location(), nil, "\u0001\u0002")

      assert_errors expected, '?\u{0001 0002}', [
        ["Invalid Unicode escape sequence; multiple codepoints are not allowed in a character literal", 9..12]
      ]
    end

    def test_invalid_hex_escape
      assert_errors expression('"\\xx"'), '"\\xx"', [
        ["Invalid hexadecimal escape sequence", 1..3],
      ]
    end

    def test_do_not_allow_more_than_6_hexadecimal_digits_in_u_Unicode_character_notation
      expected = StringNode(0, Location(), Location(), Location(), "\u0001")

      assert_errors expected, '"\u{0000001}"', [
        ["Invalid Unicode escape sequence; maximum length is 6 digits", 4..11],
      ]
    end

    def test_do_not_allow_characters_other_than_0_9_a_f_and_A_F_in_u_Unicode_character_notation
      expected = StringNode(0, Location(), Location(), Location(), "\u0000z}")

      assert_errors expected, '"\u{000z}"', [
        ["Invalid Unicode escape sequence", 7..7],
      ]
    end

    def test_unterminated_unicode_brackets_should_be_a_syntax_error
      assert_errors expression('?\\u{3'), '?\\u{3', [
        ["Invalid Unicode escape sequence; needs closing `}`", 1..5],
      ]
    end

    def test_method_parameters_after_block
      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode(
          [],
          [],
          nil,
          [RequiredParameterNode(:a)],
          [],
          nil,
          BlockParameterNode(:block, Location(), Location())
        ),
        nil,
        [:block, :a],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )
      assert_errors expected, "def foo(&block, a)\nend", [
        ["Unexpected parameter order", 16..17]
      ]
    end

    def test_method_with_arguments_after_anonymous_block
      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([], [], nil, [RequiredParameterNode(:a)], [], nil, BlockParameterNode(nil, nil, Location())),
        nil,
        [:&, :a],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(&, a)\nend", [
        ["Unexpected parameter order", 11..12]
      ]
    end

    def test_method_parameters_after_arguments_forwarding
      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode(
          [],
          [],
          nil,
          [RequiredParameterNode(:a)],
          [],
          ForwardingParameterNode(),
          nil
        ),
        nil,
        [:"...", :a],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )
      assert_errors expected, "def foo(..., a)\nend", [
        ["Unexpected parameter order", 13..14]
      ]
    end

    def test_keywords_parameters_before_required_parameters
      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode(
          [],
          [],
          nil,
          [RequiredParameterNode(:a)],
          [KeywordParameterNode(:b, Location(), nil)],
          nil,
          nil
        ),
        nil,
        [:b, :a],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )
      assert_errors expected, "def foo(b:, a)\nend", [
        ["Unexpected parameter order", 12..13]
      ]
    end

    def test_rest_keywords_parameters_before_required_parameters
      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode(
          [],
          [],
          nil,
          [],
          [KeywordParameterNode(:b, Location(), nil)],
          KeywordRestParameterNode(:rest, Location(), Location()),
          nil
        ),
        nil,
        [:rest, :b],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(**rest, b:)\nend", [
        ["Unexpected parameter order", 16..18]
      ]
    end

    def test_double_arguments_forwarding
      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([], [], nil, [], [], ForwardingParameterNode(), nil),
        nil,
        [:"..."],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(..., ...)\nend", [
        ["Unexpected parameter order", 13..16]
      ]
    end

    def test_multiple_error_in_parameters_order
      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode(
          [],
          [],
          nil,
          [RequiredParameterNode(:a)],
          [KeywordParameterNode(:b, Location(), nil)],
          KeywordRestParameterNode(:args, Location(), Location()),
          nil
        ),
        nil,
        [:args, :a, :b],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(**args, a, b:)\nend", [
        ["Unexpected parameter order", 16..17],
        ["Unexpected parameter order", 19..21]
      ]
    end

    def test_switching_to_optional_arguments_twice
      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode(
          [],
          [],
          nil,
          [RequiredParameterNode(:a)],
          [KeywordParameterNode(:b, Location(), nil)],
          KeywordRestParameterNode(:args, Location(), Location()),
          nil
        ),
        nil,
        [:args, :a, :b],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location(),
      )

      assert_errors expected, "def foo(**args, a, b:)\nend", [
        ["Unexpected parameter order", 16..17],
        ["Unexpected parameter order", 19..21]
      ]
    end

    def test_switching_to_named_arguments_twice
      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode(
          [],
          [],
          nil,
          [RequiredParameterNode(:a)],
          [KeywordParameterNode(:b, Location(), nil)],
          KeywordRestParameterNode(:args, Location(), Location()),
          nil
        ),
        nil,
        [:args, :a, :b],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location(),
      )

      assert_errors expected, "def foo(**args, a, b:)\nend", [
        ["Unexpected parameter order", 16..17],
        ["Unexpected parameter order", 19..21]
      ]
    end

    def test_returning_to_optional_parameters_multiple_times
      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode(
          [RequiredParameterNode(:a)],
          [
            OptionalParameterNode(:b, Location(), Location(), IntegerNode(IntegerBaseFlags::DECIMAL)),
            OptionalParameterNode(:d, Location(), Location(), IntegerNode(IntegerBaseFlags::DECIMAL))
          ],
          nil,
          [RequiredParameterNode(:c), RequiredParameterNode(:e)],
          [],
          nil,
          nil
        ),
        nil,
        [:a, :b, :c, :d, :e],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location(),
      )

      assert_errors expected, "def foo(a, b = 1, c, d = 2, e)\nend", [
        ["Unexpected parameter order", 23..24]
      ]
    end

    def test_case_without_when_clauses_errors_on_else_clause
      expected = CaseNode(
        SymbolNode(Location(), Location(), nil, "a"),
        [],
        ElseNode(Location(), nil, Location()),
        Location(),
        Location()
      )

      assert_errors expected, "case :a\nelse\nend", [
        ["Expected a `when` or `in` clause after `case`", 0..4]
      ]
    end

    def test_case_without_clauses
      expected = CaseNode(
        SymbolNode(Location(), Location(), nil, "a"),
        [],
        nil,
        Location(),
        Location()
      )

      assert_errors expected, "case :a\nend", [
        ["Expected a `when` or `in` clause after `case`", 0..4]
      ]
    end

    def test_setter_method_cannot_be_defined_in_an_endless_method_definition
      expected = DefNode(
        :a=,
        Location(),
        nil,
        nil,
        StatementsNode([IntegerNode(IntegerBaseFlags::DECIMAL)]),
        [],
        Location(),
        nil,
        Location(),
        Location(),
        Location(),
        nil
      )

      assert_errors expected, "def a=() = 42", [
        ["Invalid method name; a setter method cannot be defined in an endless method definition", 4..6]
      ]
    end

    def test_do_not_allow_forward_arguments_in_lambda_literals
      expected = LambdaNode(
        [:"..."],
        Location(),
        Location(),
        Location(),
        BlockParametersNode(ParametersNode([], [], nil, [], [], ForwardingParameterNode(), nil), [], Location(), Location()),
        nil
      )

      assert_errors expected, "->(...) {}", [
        ["Unexpected `...` when the parent method is not forwarding", 3..6]
      ]
    end

    def test_do_not_allow_forward_arguments_in_blocks
      expected = CallNode(
        nil,
        nil,
        Location(),
        nil,
        nil,
        nil,
        BlockNode(
          [:"..."],
          BlockParametersNode(ParametersNode([], [], nil, [], [], ForwardingParameterNode(), nil), [], Location(), Location()),
          nil,
          Location(),
          Location()
        ),
        0,
        :a
      )

      assert_errors expected, "a {|...|}", [
        ["Unexpected `...` when the parent method is not forwarding", 4..7]
      ]
    end

    def test_dont_allow_return_inside_class_body
      expected = ClassNode(
        [],
        Location(),
        ConstantReadNode(:A),
        nil,
        nil,
        StatementsNode([ReturnNode(Location(), nil)]),
        Location(),
        :A
      )

      assert_errors expected, "class A; return; end", [
        ["Invalid `return` in a class or module body", 15..16]
      ]
    end

    def test_dont_allow_return_inside_module_body
      expected = ModuleNode(
        [],
        Location(),
        ConstantReadNode(:A),
        StatementsNode([ReturnNode(Location(), nil)]),
        Location(),
        :A
      )

      assert_errors expected, "module A; return; end", [
        ["Invalid `return` in a class or module body", 16..17]
      ]
    end

    def test_dont_allow_setting_to_back_and_nth_reference
      expected = BeginNode(
        Location(),
        StatementsNode([
          GlobalVariableWriteNode(:$+, Location(), NilNode(), Location()),
          GlobalVariableWriteNode(:$1466, Location(), NilNode(), Location())
        ]),
        nil,
        nil,
        nil,
        Location()
      )

      assert_errors expected, "begin\n$+ = nil\n$1466 = nil\nend", [
        ["Immutable variable as a write target", 6..8],
        ["Immutable variable as a write target", 15..20]
      ]
    end

    def test_duplicated_parameter_names
      # For some reason, Ripper reports no error for Ruby 3.0 when you have
      # duplicated parameter names for positional parameters.
      unless RUBY_VERSION < "3.1.0"
        expected = DefNode(
          :foo,
          Location(),
          nil,
          ParametersNode([RequiredParameterNode(:a), RequiredParameterNode(:b), RequiredParameterNode(:a)], [], nil, [], [], nil, nil),
          nil,
          [:a, :b],
          Location(),
          nil,
          Location(),
          Location(),
          nil,
          Location()
        )

        assert_errors expected, "def foo(a,b,a);end", [
          ["Repeated parameter name", 12..13]
        ]
      end

      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([RequiredParameterNode(:a), RequiredParameterNode(:b)], [], RestParameterNode(:a, Location(), Location()), [], [], nil, nil),
        nil,
        [:a, :b],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(a,b,*a);end", [
        ["Repeated parameter name", 13..14]
      ]

      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([RequiredParameterNode(:a), RequiredParameterNode(:b)], [], nil, [], [], KeywordRestParameterNode(:a, Location(), Location()), nil),
        nil,
        [:a, :b],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(a,b,**a);end", [
        ["Repeated parameter name", 14..15]
      ]

      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([RequiredParameterNode(:a), RequiredParameterNode(:b)], [], nil, [], [], nil, BlockParameterNode(:a, Location(), Location())),
        nil,
        [:a, :b],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(a,b,&a);end", [
        ["Repeated parameter name", 13..14]
      ]

      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([], [OptionalParameterNode(:a, Location(), Location(), IntegerNode(IntegerBaseFlags::DECIMAL))], RestParameterNode(:c, Location(), Location()), [RequiredParameterNode(:b)], [], nil, nil),
        nil,
        [:a, :b, :c],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(a = 1,b,*c);end", [["Unexpected parameter `*`", 16..17]]
    end

    def test_invalid_message_name
      result = Prism.parse("+.@foo,+=foo")
      assert_equal :"", result.value.statements.body.first.write_name
    end

    def test_invalid_operator_write_fcall
      source = "foo! += 1"
      assert_errors expression(source), source, [
        ["Unexpected write target", 0..4]
      ]
    end

    def test_invalid_operator_write_dot
      source = "foo.+= 1"
      assert_errors expression(source), source, [
        ["Unexpected write target", 5..6]
      ]
    end

    def test_unterminated_global_variable
      assert_errors expression("$"), "$", [
        ["Invalid global variable", 0..1]
      ]
    end

    def test_invalid_global_variable_write
      assert_errors expression("$',"), "$',", [
        ["Immutable variable as a write target", 0..2],
        ["Unexpected write target", 0..3]
      ]
    end

    def test_invalid_multi_target
      error_messages = ["Unexpected write target"]
      immutable = "Immutable variable as a write target"

      assert_error_messages "foo,", error_messages
      assert_error_messages "foo = 1; foo,", error_messages
      assert_error_messages "foo.bar,", error_messages
      assert_error_messages "*foo,", error_messages
      assert_error_messages "@foo,", error_messages
      assert_error_messages "@@foo,", error_messages
      assert_error_messages "$foo,", error_messages
      assert_error_messages "$1,", [immutable, *error_messages]
      assert_error_messages "$+,", [immutable, *error_messages]
      assert_error_messages "Foo,", error_messages
      assert_error_messages "::Foo,", error_messages
      assert_error_messages "Foo::Foo,", error_messages
      assert_error_messages "Foo::foo,", error_messages
      assert_error_messages "foo[foo],", error_messages
      assert_error_messages "(foo, bar)", error_messages
    end

    def test_call_with_block_and_write
      source = "foo {} &&= 1"
      assert_errors expression(source), source, [
        ["Unexpected write target", 0..6],
        ["Unexpected operator after a call with a block", 7..10]
      ]
    end

    def test_call_with_block_or_write
      source = "foo {} ||= 1"
      assert_errors expression(source), source, [
        ["Unexpected write target", 0..6],
        ["Unexpected operator after a call with a block", 7..10]
      ]
    end

    def test_call_with_block_operator_write
      source = "foo {} += 1"
      assert_errors expression(source), source, [
        ["Unexpected write target", 0..6],
        ["Unexpected operator after a call with a block", 7..9]
      ]
    end

    def test_writing_numbered_parameter
      assert_errors expression("-> { _1 = 0 }"), "-> { _1 = 0 }", [
        ["Token reserved for a numbered parameter", 5..7]
      ]
    end

    def test_targeting_numbered_parameter
      assert_errors expression("-> { _1, = 0 }"), "-> { _1, = 0 }", [
        ["Token reserved for a numbered parameter", 5..7]
      ]
    end

    def test_double_scope_numbered_parameters
      source = "-> { _1 + -> { _2 } }"
      errors = [["Numbered parameter is already used in outer scope", 15..17]]

      assert_errors expression(source), source, errors, compare_ripper: false
    end

    def test_invalid_number_underscores
      error_messages = ["Invalid underscore placement in number"]

      assert_error_messages "1__1", error_messages
      assert_error_messages "0b1__1", error_messages
      assert_error_messages "0o1__1", error_messages
      assert_error_messages "01__1", error_messages
      assert_error_messages "0d1__1", error_messages
      assert_error_messages "0x1__1", error_messages

      assert_error_messages "1_1_", error_messages
      assert_error_messages "0b1_1_", error_messages
      assert_error_messages "0o1_1_", error_messages
      assert_error_messages "01_1_", error_messages
      assert_error_messages "0d1_1_", error_messages
      assert_error_messages "0x1_1_", error_messages
    end

    def test_alnum_delimiters
      error_messages = ["Invalid `%` token"]

      assert_error_messages "%qXfooX", error_messages
      assert_error_messages "%QXfooX", error_messages
      assert_error_messages "%wXfooX", error_messages
      assert_error_messages "%WxfooX", error_messages
      assert_error_messages "%iXfooX", error_messages
      assert_error_messages "%IXfooX", error_messages
      assert_error_messages "%xXfooX", error_messages
      assert_error_messages "%rXfooX", error_messages
      assert_error_messages "%sXfooX", error_messages
    end

    def test_begin_at_toplevel
      source = "def foo; BEGIN {}; end"
      assert_errors expression(source), source, [
        ["BEGIN is permitted only at toplevel", 9..14],
      ]
    end

    def test_numbered_parameters_in_block_arguments
      source = "foo { |_1| }"
      assert_errors expression(source), source, [
        ["Token reserved for a numbered parameter", 7..9],
      ]
    end

    def test_conditional_predicate_closed
      source = "if 0 0; elsif 0 0; end\nunless 0 0; end"
      assert_errors expression(source), source, [
        ["Expected `then` or `;` or '\n" + "'", 5..6],
        ["Expected `then` or `;` or '\n" + "'", 16..17],
        ["Expected `then` or `;` or '\n" + "'", 32..33],
      ]
    end

    def test_parameter_name_ending_with_bang_or_question_mark
      source = "def foo(x!,y?); end"
      errors = [
        ["Unexpected name for a parameter", 8..10],
        ["Unexpected name for a parameter", 11..13]
      ]
      assert_errors expression(source), source, errors, compare_ripper: false
    end

    def test_class_name
      source = "class 0.X end"
      assert_errors expression(source), source, [
        ["Expected a constant name after `class`", 6..9],
      ]
    end

    def test_loop_conditional_is_closed
      source = "while 0 0; foo; end; until 0 0; foo; end"
      assert_errors expression(source), source, [
        ["Expected a predicate expression for the `while` statement", 7..7],
        ["Expected a predicate expression for the `until` statement", 28..28],
      ]
    end

    def test_forwarding_arg_after_keyword_rest
      source = "def f(**,...);end"
      assert_errors expression(source), source, [
        ["Unexpected `...` in parameters", 9..12],
      ]
    end

    def test_semicolon_after_inheritance_operator
      source = "class Foo < Bar end"
      assert_errors expression(source), source, [
        ["Unexpected `end`, expecting ';' or '\n'", 15..15],
      ]
    end

    def test_shadow_args_in_lambda
      source = "->a;b{}"
      assert_errors expression(source), source, [
        ["Expected a `do` keyword or a `{` to open the lambda block", 3..3],
        ["Expected a newline or semicolon after the statement", 7..7],
        ["Cannot parse the expression", 7..7],
        ["Expected a lambda block beginning with `do` to end with `end`", 7..7],
      ]
    end

    def test_shadow_args_in_block
      source = "tap{|a;a|}"
      assert_errors expression(source), source, [
        ["Repeated parameter name", 7..8],
      ]
    end

    def test_repeated_parameter_name_in_destructured_params
      source = "def f(a, (b, (a))); end"
      # In Ruby 3.0.x, `Ripper.sexp_raw` does not return `nil` for this case.
      compare_ripper = RUBY_ENGINE == "ruby" && (RUBY_VERSION.split('.').map { |x| x.to_i } <=> [3, 1]) >= 1
      assert_errors expression(source), source, [
        ["Repeated parameter name", 14..15],
      ], compare_ripper: compare_ripper
    end

    def test_assign_to_numbered_parameter
      source = "
        a in _1
        a => _1
        1 => a, _1
        1 in a, _1
      "
      assert_errors expression(source), source, [
        ["Token reserved for a numbered parameter", 14..16],
        ["Token reserved for a numbered parameter", 30..32],
        ["Token reserved for a numbered parameter", 49..51],
        ["Token reserved for a numbered parameter", 68..70],
      ]
    end

    def test_symbol_in_keyword_parameter
      source = "def foo(x:'y':); end"
      assert_errors expression(source), source, [
        ["Expected a closing delimiter for the string literal", 14..14],
      ]
    end

    def test_symbol_in_hash
      source = "{x:'y':}"
      assert_errors expression(source), source, [
        ["Expected a closing delimiter for the string literal", 7..7],
      ]
    end

    private

    def assert_errors(expected, source, errors, compare_ripper: RUBY_ENGINE == "ruby")
      # Ripper behaves differently on JRuby/TruffleRuby, so only check this on CRuby
      assert_nil Ripper.sexp_raw(source) if compare_ripper

      result = Prism.parse(source)
      node = result.value.statements.body.last

      assert_equal_nodes(expected, node, compare_location: false)
      assert_equal(errors, result.errors.map { |e| [e.message, e.location.start_offset..e.location.end_offset] })
    end

    def assert_error_messages(source, errors, compare_ripper: RUBY_ENGINE == "ruby")
      assert_nil Ripper.sexp_raw(source) if compare_ripper
      result = Prism.parse(source)
      assert_equal(errors, result.errors.map(&:message))
    end

    def expression(source)
      Prism.parse(source).value.statements.body.last
    end
  end
end
