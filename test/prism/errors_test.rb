# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class ErrorsTest < TestCase
    include DSL

    def test_constant_path_with_invalid_token_after
      assert_error_messages "A::$b", [
        "expected a constant after the `::` operator",
        "expected a newline or semicolon after the statement"
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
        ["expected a constant name after `module`", 20..20]
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
        ["expected an index after `for`", 0..3]
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
        ["expected an index after `for`", 0..3],
        ["expected an `in` after the index in a `for` statement", 3..3],
        ["expected a collection after the `in` in a `for` statement", 3..3]
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
        ["expected a `{` after `BEGIN`", 5..5]
      ]
    end

    def test_pre_execution_context
      expected = PreExecutionNode(
        StatementsNode([
          CallNode(
            0,
            expression("1"),
            nil,
            :+,
            Location(),
            nil,
            ArgumentsNode(0, [MissingNode()]),
            nil,
            nil
          )
        ]),
        Location(),
        Location(),
        Location()
      )

      assert_errors expected, "BEGIN { 1 + }", [
        ["expected an expression after the operator", 11..11]
      ]
    end

    def test_unterminated_embdoc
      assert_errors expression("1"), "1\n=begin\n", [
        ["could not find a terminator for the embedded document", 2..9]
      ]
    end

    def test_unterminated_i_list
      assert_errors expression("%i["), "%i[", [
        ["expected a closing delimiter for the `%i` list", 0..3]
      ]
    end

    def test_unterminated_w_list
      assert_errors expression("%w["), "%w[", [
        ["expected a closing delimiter for the `%w` list", 0..3]
      ]
    end

    def test_unterminated_W_list
      assert_errors expression("%W["), "%W[", [
        ["expected a closing delimiter for the `%W` list", 0..3]
      ]
    end

    def test_unterminated_regular_expression
      assert_errors expression("/hello"), "/hello", [
        ["expected a closing delimiter for the regular expression", 0..1]
      ]
    end

    def test_unterminated_regular_expression_with_heredoc
      source = "<<-END + /b\nEND\n"

      assert_errors expression(source), source, [
        ["expected a closing delimiter for the regular expression", 9..10]
      ]
    end

    def test_unterminated_xstring
      assert_errors expression("`hello"), "`hello", [
        ["expected a closing delimiter for the `%x` or backtick string", 0..1]
      ]
    end

    def test_unterminated_interpolated_string
      expr = expression('"hello')
      assert_errors expr, '"hello', [
        ["expected a closing delimiter for the string literal", 6..6]
      ]
      assert_equal expr.unescaped, "hello"
      assert_equal expr.closing, ""
    end

    def test_unterminated_string
      expr = expression("'hello")
      assert_errors expr, "'hello", [
        ["expected a closing delimiter for the string literal", 0..1]
      ]
      assert_equal expr.unescaped, "hello"
      assert_equal expr.closing, ""
    end

    def test_unterminated_empty_string
      expr = expression('"')
      assert_errors expr, '"', [
        ["expected a closing delimiter for the string literal", 1..1]
      ]
      assert_equal expr.unescaped, ""
      assert_equal expr.closing, ""
    end

    def test_incomplete_instance_var_string
      assert_errors expression('%@#@@#'), '%@#@@#', [
        ["incomplete instance variable", 4..5],
        ["expected a newline or semicolon after the statement", 4..4]
      ]
    end

    def test_unterminated_s_symbol
      assert_errors expression("%s[abc"), "%s[abc", [
        ["expected a closing delimiter for the dynamic symbol", 0..3]
      ]
    end

    def test_unterminated_parenthesized_expression
      assert_errors expression('(1 + 2'), '(1 + 2', [
        ["expected a newline or semicolon after the statement", 6..6],
        ["cannot parse the expression", 6..6],
        ["expected a matching `)`", 6..6]
      ]
    end

    def test_missing_terminator_in_parentheses
      assert_error_messages "(0 0)", [
        "expected a newline or semicolon after the statement"
      ]
    end

    def test_unterminated_argument_expression
      assert_errors expression('a %'), 'a %', [
        ["invalid `%` token", 2..3],
        ["expected an expression after the operator", 3..3],
      ]
    end

    def test_unterminated_interpolated_symbol
      assert_error_messages ":\"#", [
        "expected a closing delimiter for the interpolated symbol"
      ]
    end

    def test_cr_without_lf_in_percent_expression
      assert_errors expression("%\r"), "%\r", [
        ["invalid `%` token", 0..2],
      ]
    end

    def test_1_2_3
      assert_errors expression("(1, 2, 3)"), "(1, 2, 3)", [
        ["expected a newline or semicolon after the statement", 2..2],
        ["cannot parse the expression", 2..2],
        ["expected a matching `)`", 2..2],
        ["expected a newline or semicolon after the statement", 2..2],
        ["cannot parse the expression", 2..2],
        ["expected a newline or semicolon after the statement", 5..5],
        ["cannot parse the expression", 5..5],
        ["expected a newline or semicolon after the statement", 8..8],
        ["cannot parse the expression", 8..8]
      ]
    end

    def test_return_1_2_3
      assert_error_messages "return(1, 2, 3)", [
        "expected a newline or semicolon after the statement",
        "cannot parse the expression",
        "expected a matching `)`",
        "expected a newline or semicolon after the statement",
        "cannot parse the expression"
      ]
    end

    def test_return_1
      assert_errors expression("return 1,;"), "return 1,;", [
        ["expected an argument", 9..9]
      ]
    end

    def test_next_1_2_3
      assert_errors expression("next(1, 2, 3)"), "next(1, 2, 3)", [
        ["expected a newline or semicolon after the statement", 6..6],
        ["cannot parse the expression", 6..6],
        ["expected a matching `)`", 6..6],
        ["expected a newline or semicolon after the statement", 12..12],
        ["cannot parse the expression", 12..12]
      ]
    end

    def test_next_1
      assert_errors expression("next 1,;"), "next 1,;", [
        ["expected an argument", 7..7]
      ]
    end

    def test_break_1_2_3
      assert_errors expression("break(1, 2, 3)"), "break(1, 2, 3)", [
        ["expected a newline or semicolon after the statement", 7..7],
        ["cannot parse the expression", 7..7],
        ["expected a matching `)`", 7..7],
        ["expected a newline or semicolon after the statement", 13..13],
        ["cannot parse the expression", 13..13]
      ]
    end

    def test_break_1
      assert_errors expression("break 1,;"), "break 1,;", [
        ["expected an argument", 8..8]
      ]
    end

    def test_argument_forwarding_when_parent_is_not_forwarding
      assert_errors expression('def a(x, y, z); b(...); end'), 'def a(x, y, z); b(...); end', [
        ["unexpected `...` when the parent method is not forwarding", 18..21]
      ]
    end

    def test_argument_forwarding_only_effects_its_own_internals
      assert_errors expression('def a(...); b(...); end; def c(x, y, z); b(...); end'),
        'def a(...); b(...); end; def c(x, y, z); b(...); end', [
          ["unexpected `...` when the parent method is not forwarding", 43..46]
        ]
    end

    def test_top_level_constant_with_downcased_identifier
      assert_error_messages "::foo", [
        "expected a constant after the `::` operator",
        "expected a newline or semicolon after the statement"
      ]
    end

    def test_top_level_constant_starting_with_downcased_identifier
      assert_error_messages "::foo::A", [
        "expected a constant after the `::` operator",
        "expected a newline or semicolon after the statement"
      ]
    end

    def test_aliasing_global_variable_with_non_global_variable
      assert_errors expression("alias $a b"), "alias $a b", [
        ["invalid argument being passed to `alias`; expected a bare word, symbol, constant, or global variable", 9..10]
      ]
    end

    def test_aliasing_non_global_variable_with_global_variable
      assert_errors expression("alias a $b"), "alias a $b", [
        ["invalid argument being passed to `alias`; expected a bare word, symbol, constant, or global variable", 8..10]
      ]
    end

    def test_aliasing_global_variable_with_global_number_variable
      assert_errors expression("alias $a $1"), "alias $a $1", [
        ["invalid argument being passed to `alias`; expected a bare word, symbol, constant, or global variable", 9..11]
      ]
    end

    def test_def_with_expression_receiver_and_no_identifier
      assert_errors expression("def (a); end"), "def (a); end", [
        ["expected a `.` or `::` after the receiver in a method definition", 7..7],
        ["expected a method name", 7..7]
      ]
    end

    def test_def_with_multiple_statements_receiver
      assert_errors expression("def (\na\nb\n).c; end"), "def (\na\nb\n).c; end", [
        ["expected a matching `)`", 7..7],
        ["expected a `.` or `::` after the receiver in a method definition", 7..7],
        ["expected a method name", 7..7],
        ["cannot parse the expression", 10..10],
        ["cannot parse the expression", 11..11]
      ]
    end

    def test_def_with_empty_expression_receiver
      assert_errors expression("def ().a; end"), "def ().a; end", [
        ["expected a receiver for the method definition", 5..5]
      ]
    end

    def test_block_beginning_with_brace_and_ending_with_end
      assert_error_messages "x.each { x end", [
        "expected a newline or semicolon after the statement",
        "cannot parse the expression",
        "cannot parse the expression",
        "expected a block beginning with `{` to end with `}`"
      ]
    end

    def test_double_splat_followed_by_splat_argument
      expected = CallNode(
        0,
        nil,
        nil,
        :a,
        Location(),
        Location(),
        ArgumentsNode(1, [
          KeywordHashNode(0, [AssocSplatNode(expression("kwargs"), Location())]),
          SplatNode(Location(), expression("args"))
        ]),
        Location(),
        nil
      )

      assert_errors expected, "a(**kwargs, *args)", [
        ["unexpected `*` splat argument after a `**` keyword splat argument", 12..17]
      ]
    end

    def test_arguments_after_block
      expected = CallNode(
        0,
        nil,
        nil,
        :a,
        Location(),
        Location(),
        ArgumentsNode(0, [expression("foo")]),
        Location(),
        BlockArgumentNode(expression("block"), Location())
      )

      assert_errors expected, "a(&block, foo)", [
        ["unexpected argument after a block argument", 10..13]
      ]
    end

    def test_arguments_binding_power_for_and
      assert_error_messages "foo(*bar and baz)", [
        "expected a `)` to close the arguments",
        "expected a newline or semicolon after the statement",
        "cannot parse the expression"
      ]
    end

    def test_splat_argument_after_keyword_argument
      expected = CallNode(
        0,
        nil,
        nil,
        :a,
        Location(),
        Location(),
        ArgumentsNode(0, [
          KeywordHashNode(1, [
            AssocNode(
              SymbolNode(0, nil, Location(), Location(), "foo"),
              expression("bar"),
              nil
            )
          ]),
          SplatNode(Location(), expression("args"))
        ]),
        Location(),
        nil
      )

      assert_errors expected, "a(foo: bar, *args)", [
        ["unexpected `*` splat argument after a `**` keyword splat argument", 12..17]
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
        0,
        Location(),
        nil,
        nil,
        nil,
        nil,
        Location()
      )

      assert_errors expected, "def foo;module A;end;end", [
        ["unexpected module definition in a method definition", 8..14]
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
            0,
            nil,
            nil,
            :bar,
            Location(),
            nil,
            nil,
            nil,
            BlockNode(
              [],
              0,
              nil,
              StatementsNode([ModuleNode([], Location(), ConstantReadNode(:Foo), nil, Location(), :Foo)]),
              Location(),
              Location()
            )
          )]
        ),
        [],
        0,
        Location(),
        nil,
        nil,
        nil,
        nil,
        Location()
      )

      assert_errors expected, <<~RUBY, [["unexpected module definition in a method definition", 21..27]]
        def foo
          bar do
            module Foo;end
          end
        end
      RUBY
    end

    def test_module_definition_in_method_defs
      source = <<~RUBY
        def foo(bar = module A;end);end
        def foo;rescue;module A;end;end
        def foo;ensure;module A;end;end
      RUBY
      message = "unexpected module definition in a method definition"
      assert_errors expression(source), source, [
        [message, 14..20],
        [message, 47..53],
        [message, 79..85],
      ]
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
        0,
        Location(),
        nil,
        nil,
        nil,
        nil,
        Location()
      )

      assert_errors expected, "def foo;class A;end;end", [
        ["unexpected class definition in a method definition", 8..13]
      ]
    end

    def test_class_definition_in_method_defs
      source = <<~RUBY
        def foo(bar = class A;end);end
        def foo;rescue;class A;end;end
        def foo;ensure;class A;end;end
      RUBY
      message = "unexpected class definition in a method definition"
      assert_errors expression(source), source, [
        [message, 14..19],
        [message, 46..51],
        [message, 77..82],
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
        4,
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(A, @a, $A, @@a);end", [
        ["invalid formal argument; formal argument cannot be a constant", 8..9],
        ["invalid formal argument; formal argument cannot be an instance variable", 11..13],
        ["invalid formal argument; formal argument cannot be a global variable", 15..17],
        ["invalid formal argument; formal argument cannot be a class variable", 19..22],
      ]
    end

    def test_cannot_assign_to_a_reserved_numbered_parameter
      expected = BeginNode(
        Location(),
        StatementsNode([
          LocalVariableWriteNode(:_1, 0, Location(), SymbolNode(0, Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_2, 0, Location(), SymbolNode(0, Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_3, 0, Location(), SymbolNode(0, Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_4, 0, Location(), SymbolNode(0, Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_5, 0, Location(), SymbolNode(0, Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_6, 0, Location(), SymbolNode(0, Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_7, 0, Location(), SymbolNode(0, Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_8, 0, Location(), SymbolNode(0, Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_9, 0, Location(), SymbolNode(0, Location(), Location(), nil, "a"), Location()),
          LocalVariableWriteNode(:_10, 0, Location(), SymbolNode(0, Location(), Location(), nil, "a"), Location())
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
        ["_1 is reserved for numbered parameters", 8..10],
        ["_2 is reserved for numbered parameters", 14..16],
        ["_3 is reserved for numbered parameters", 20..22],
        ["_4 is reserved for numbered parameters", 26..28],
        ["_5 is reserved for numbered parameters", 32..34],
        ["_6 is reserved for numbered parameters", 40..42],
        ["_7 is reserved for numbered parameters", 46..48],
        ["_8 is reserved for numbered parameters", 52..54],
        ["_9 is reserved for numbered parameters", 58..60],
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
        3,
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(a,b,c,);end", [
        ["unexpected `,` in parameters", 13..14]
      ]
    end

    def test_do_not_allow_trailing_commas_in_lambda_parameters
      expected = LambdaNode(
        [:a, :b],
        2,
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
        ["unexpected `,` in parameters", 8..9]
      ]
    end

    def test_do_not_allow_multiple_codepoints_in_a_single_character_literal
      expected = StringNode(StringFlags::FORCED_UTF8_ENCODING, Location(), Location(), nil, "\u0001\u0002")

      assert_errors expected, '?\u{0001 0002}', [
        ["invalid Unicode escape sequence; multiple codepoints are not allowed in a character literal", 9..12]
      ]
    end

    def test_invalid_hex_escape
      assert_errors expression('"\\xx"'), '"\\xx"', [
        ["invalid hexadecimal escape sequence", 1..3],
      ]
    end

    def test_do_not_allow_more_than_6_hexadecimal_digits_in_u_Unicode_character_notation
      expected = StringNode(0, Location(), Location(), Location(), "\u0001")

      assert_errors expected, '"\u{0000001}"', [
        ["invalid Unicode escape sequence; maximum length is 6 digits", 4..11],
      ]
    end

    def test_do_not_allow_characters_other_than_0_9_a_f_and_A_F_in_u_Unicode_character_notation
      expected = StringNode(0, Location(), Location(), Location(), "\u0000z}")

      assert_errors expected, '"\u{000z}"', [
        ["invalid Unicode escape sequence", 7..7],
      ]
    end

    def test_unterminated_unicode_brackets_should_be_a_syntax_error
      assert_errors expression('?\\u{3'), '?\\u{3', [
        ["invalid Unicode escape sequence; needs closing `}`", 1..5],
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
        2,
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )
      assert_errors expected, "def foo(&block, a)\nend", [
        ["unexpected parameter order", 16..17]
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
        2,
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(&, a)\nend", [
        ["unexpected parameter order", 11..12]
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
        2,
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )
      assert_errors expected, "def foo(..., a)\nend", [
        ["unexpected parameter order", 13..14]
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
          [RequiredKeywordParameterNode(:b, Location())],
          nil,
          nil
        ),
        nil,
        [:b, :a],
        2,
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )
      assert_errors expected, "def foo(b:, a)\nend", [
        ["unexpected parameter order", 12..13]
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
          [RequiredKeywordParameterNode(:b, Location())],
          KeywordRestParameterNode(:rest, Location(), Location()),
          nil
        ),
        nil,
        [:rest, :b],
        2,
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(**rest, b:)\nend", [
        ["unexpected parameter order", 16..18]
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
        1,
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(..., ...)\nend", [
        ["unexpected parameter order", 13..16]
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
          [RequiredKeywordParameterNode(:b, Location())],
          KeywordRestParameterNode(:args, Location(), Location()),
          nil
        ),
        nil,
        [:args, :a, :b],
        3,
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(**args, a, b:)\nend", [
        ["unexpected parameter order", 16..17],
        ["unexpected parameter order", 19..21]
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
          [RequiredKeywordParameterNode(:b, Location())],
          KeywordRestParameterNode(:args, Location(), Location()),
          nil
        ),
        nil,
        [:args, :a, :b],
        3,
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location(),
      )

      assert_errors expected, "def foo(**args, a, b:)\nend", [
        ["unexpected parameter order", 16..17],
        ["unexpected parameter order", 19..21]
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
          [RequiredKeywordParameterNode(:b, Location())],
          KeywordRestParameterNode(:args, Location(), Location()),
          nil
        ),
        nil,
        [:args, :a, :b],
        3,
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location(),
      )

      assert_errors expected, "def foo(**args, a, b:)\nend", [
        ["unexpected parameter order", 16..17],
        ["unexpected parameter order", 19..21]
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
        5,
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location(),
      )

      assert_errors expected, "def foo(a, b = 1, c, d = 2, e)\nend", [
        ["unexpected parameter order", 23..24]
      ]
    end

    def test_case_without_when_clauses_errors_on_else_clause
      expected = CaseMatchNode(
        SymbolNode(0, Location(), Location(), nil, "a"),
        [],
        ElseNode(Location(), nil, Location()),
        Location(),
        Location()
      )

      assert_errors expected, "case :a\nelse\nend", [
        ["expected a `when` or `in` clause after `case`", 0..4]
      ]
    end

    def test_case_without_clauses
      expected = CaseNode(
        SymbolNode(0, Location(), Location(), nil, "a"),
        [],
        nil,
        Location(),
        Location()
      )

      assert_errors expected, "case :a\nend", [
        ["expected a `when` or `in` clause after `case`", 0..4]
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
        0,
        Location(),
        nil,
        Location(),
        Location(),
        Location(),
        nil
      )

      assert_errors expected, "def a=() = 42", [
        ["invalid method name; a setter method cannot be defined in an endless method definition", 4..6]
      ]
    end

    def test_do_not_allow_forward_arguments_in_lambda_literals
      expected = LambdaNode(
        [],
        0,
        Location(),
        Location(),
        Location(),
        BlockParametersNode(ParametersNode([], [], nil, [], [], ForwardingParameterNode(), nil), [], Location(), Location()),
        nil
      )

      assert_errors expected, "->(...) {}", [
        ["unexpected `...` when the parent method is not forwarding", 3..6]
      ]
    end

    def test_do_not_allow_forward_arguments_in_blocks
      expected = CallNode(
        0,
        nil,
        nil,
        :a,
        Location(),
        nil,
        nil,
        nil,
        BlockNode(
          [],
          0,
          BlockParametersNode(ParametersNode([], [], nil, [], [], ForwardingParameterNode(), nil), [], Location(), Location()),
          nil,
          Location(),
          Location()
        )
      )

      assert_errors expected, "a {|...|}", [
        ["unexpected `...` when the parent method is not forwarding", 4..7]
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
        ["invalid `return` in a class or module body", 15..16]
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
        ["invalid `return` in a class or module body", 16..17]
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
        ["immutable variable as a write target", 6..8],
        ["immutable variable as a write target", 15..20]
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
          2,
          Location(),
          nil,
          Location(),
          Location(),
          nil,
          Location()
        )

        assert_errors expected, "def foo(a,b,a);end", [
          ["repeated parameter name", 12..13]
        ]
      end

      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([RequiredParameterNode(:a), RequiredParameterNode(:b)], [], RestParameterNode(:a, Location(), Location()), [], [], nil, nil),
        nil,
        [:a, :b],
        2,
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(a,b,*a);end", [
        ["repeated parameter name", 13..14]
      ]

      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([RequiredParameterNode(:a), RequiredParameterNode(:b)], [], nil, [], [], KeywordRestParameterNode(:a, Location(), Location()), nil),
        nil,
        [:a, :b],
        2,
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(a,b,**a);end", [
        ["repeated parameter name", 14..15]
      ]

      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([RequiredParameterNode(:a), RequiredParameterNode(:b)], [], nil, [], [], nil, BlockParameterNode(:a, Location(), Location())),
        nil,
        [:a, :b],
        2,
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(a,b,&a);end", [
        ["repeated parameter name", 13..14]
      ]

      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([], [OptionalParameterNode(:a, Location(), Location(), IntegerNode(IntegerBaseFlags::DECIMAL))], RestParameterNode(:c, Location(), Location()), [RequiredParameterNode(:b)], [], nil, nil),
        nil,
        [:a, :b, :c],
        3,
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(a = 1,b,*c);end", [["unexpected parameter `*`", 16..17]]
    end

    def test_invalid_message_name
      result = Prism.parse("+.@foo,+=foo")
      assert_equal :"", result.value.statements.body.first.write_name
    end

    def test_invalid_operator_write_fcall
      source = "foo! += 1"
      assert_errors expression(source), source, [
        ["unexpected write target", 0..4]
      ]
    end

    def test_invalid_operator_write_dot
      source = "foo.+= 1"
      assert_errors expression(source), source, [
        ["unexpected write target", 5..6]
      ]
    end

    def test_unterminated_global_variable
      assert_errors expression("$"), "$", [
        ["invalid global variable", 0..1]
      ]
    end

    def test_invalid_global_variable_write
      assert_errors expression("$',"), "$',", [
        ["immutable variable as a write target", 0..2],
        ["unexpected write target", 0..2]
      ]
    end

    def test_invalid_multi_target
      error_messages = ["unexpected write target"]
      immutable = "immutable variable as a write target"

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
      assert_error_messages "foo((foo, bar))", error_messages
      assert_error_messages "foo((*))", error_messages
      assert_error_messages "foo(((foo, bar), *))", error_messages
      assert_error_messages "(foo, bar) + 1", error_messages
      assert_error_messages "(foo, bar) in baz", error_messages
    end

    def test_call_with_block_and_write
      source = "foo {} &&= 1"
      assert_errors expression(source), source, [
        ["unexpected write target", 0..6],
        ["unexpected operator after a call with a block", 7..10]
      ]
    end

    def test_call_with_block_or_write
      source = "foo {} ||= 1"
      assert_errors expression(source), source, [
        ["unexpected write target", 0..6],
        ["unexpected operator after a call with a block", 7..10]
      ]
    end

    def test_call_with_block_operator_write
      source = "foo {} += 1"
      assert_errors expression(source), source, [
        ["unexpected write target", 0..6],
        ["unexpected operator after a call with a block", 7..9]
      ]
    end

    def test_index_call_with_block_and_write
      source = "foo[1] {} &&= 1"
      assert_errors expression(source), source, [
        ["unexpected write target", 0..9],
        ["unexpected operator after a call with arguments", 10..13],
        ["unexpected operator after a call with a block", 10..13]
      ]
    end

    def test_index_call_with_block_or_write
      source = "foo[1] {} ||= 1"
      assert_errors expression(source), source, [
        ["unexpected write target", 0..9],
        ["unexpected operator after a call with arguments", 10..13],
        ["unexpected operator after a call with a block", 10..13]
      ]
    end

    def test_index_call_with_block_operator_write
      source = "foo[1] {} += 1"
      assert_errors expression(source), source, [
        ["unexpected write target", 0..9],
        ["unexpected operator after a call with arguments", 10..12],
        ["unexpected operator after a call with a block", 10..12]
      ]
    end

    def test_writing_numbered_parameter
      assert_errors expression("-> { _1 = 0 }"), "-> { _1 = 0 }", [
        ["_1 is reserved for numbered parameters", 5..7]
      ]
    end

    def test_targeting_numbered_parameter
      assert_errors expression("-> { _1, = 0 }"), "-> { _1, = 0 }", [
        ["_1 is reserved for numbered parameters", 5..7]
      ]
    end

    def test_defining_numbered_parameter
      error_messages = ["_1 is reserved for numbered parameters"]

      assert_error_messages "def _1; end", error_messages
      assert_error_messages "def self._1; end", error_messages
    end

    def test_double_scope_numbered_parameters
      source = "-> { _1 + -> { _2 } }"
      errors = [["numbered parameter is already used in outer scope", 15..17]]

      assert_errors expression(source), source, errors, compare_ripper: false
    end

    def test_invalid_number_underscores
      error_messages = ["invalid underscore placement in number"]

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
      error_messages = ["invalid `%` token"]

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
        ["_1 is reserved for numbered parameters", 7..9],
      ]
    end

    def test_conditional_predicate_closed
      source = "if 0 0; elsif 0 0; end\nunless 0 0; end"
      assert_errors expression(source), source, [
        ["expected `then` or `;` or '\\n" + "'", 5..6],
        ["expected `then` or `;` or '\\n" + "'", 16..17],
        ["expected `then` or `;` or '\\n" + "'", 32..33],
      ]
    end

    def test_parameter_name_ending_with_bang_or_question_mark
      source = "def foo(x!,y?); end"
      errors = [
        ["unexpected name for a parameter", 8..10],
        ["unexpected name for a parameter", 11..13]
      ]
      assert_errors expression(source), source, errors, compare_ripper: false
    end

    def test_class_name
      source = "class 0.X end"
      assert_errors expression(source), source, [
        ["expected a constant name after `class`", 6..9],
      ]
    end

    def test_loop_conditional_is_closed
      source = "while 0 0; foo; end; until 0 0; foo; end"
      assert_errors expression(source), source, [
        ["expected a predicate expression for the `while` statement", 7..7],
        ["expected a predicate expression for the `until` statement", 28..28],
      ]
    end

    def test_forwarding_arg_after_keyword_rest
      source = "def f(**,...);end"
      assert_errors expression(source), source, [
        ["unexpected `...` in parameters", 9..12],
      ]
    end

    def test_semicolon_after_inheritance_operator
      source = "class Foo < Bar end"
      assert_errors expression(source), source, [
        ["unexpected `end`, expecting ';' or '\\n'", 15..15],
      ]
    end

    def test_shadow_args_in_lambda
      source = "->a;b{}"
      assert_errors expression(source), source, [
        ["expected a `do` keyword or a `{` to open the lambda block", 3..3],
        ["expected a newline or semicolon after the statement", 7..7],
        ["cannot parse the expression", 7..7],
        ["expected a lambda block beginning with `do` to end with `end`", 7..7],
      ]
    end

    def test_shadow_args_in_block
      source = "tap{|a;a|}"
      assert_errors expression(source), source, [
        ["repeated parameter name", 7..8],
      ]
    end

    def test_repeated_parameter_name_in_destructured_params
      source = "def f(a, (b, (a))); end"
      # In Ruby 3.0.x, `Ripper.sexp_raw` does not return `nil` for this case.
      compare_ripper = RUBY_ENGINE == "ruby" && (RUBY_VERSION.split('.').map { |x| x.to_i } <=> [3, 1]) >= 1
      assert_errors expression(source), source, [
        ["repeated parameter name", 14..15],
      ], compare_ripper: compare_ripper
    end

    def test_assign_to_numbered_parameter
      source = <<~RUBY
        a in _1
        a => _1
        1 => a, _1
        1 in a, _1
        /(?<_1>)/ =~ a
      RUBY

      message = "_1 is reserved for numbered parameters"
      assert_errors expression(source), source, [
        [message, 5..7],
        [message, 13..15],
        [message, 24..26],
        [message, 35..37],
        [message, 42..44]
      ]
    end

    def test_symbol_in_keyword_parameter
      source = "def foo(x:'y':); end"
      assert_errors expression(source), source, [
        ["expected a closing delimiter for the string literal", 14..14],
      ]
    end

    def test_symbol_in_hash
      source = "{x:'y':}"
      assert_errors expression(source), source, [
        ["expected a closing delimiter for the string literal", 7..7],
      ]
    end

    def test_while_endless_method
      source = "while def f = g do end"
      assert_errors expression(source), source, [
        ['expected a predicate expression for the `while` statement', 22..22],
        ['cannot parse the expression', 22..22],
        ['expected an `end` to close the `while` statement', 22..22]
      ]
    end

    def test_match_plus
      source = <<~RUBY
        a in b + c
        a => b + c
      RUBY
      message1 = 'expected a newline or semicolon after the statement'
      message2 = 'cannot parse the expression'
      assert_errors expression(source), source, [
        [message1, 6..6],
        [message2, 6..6],
        [message1, 17..17],
        [message2, 17..17],
      ]
    end

    def test_rational_number_with_exponential_portion
      source = '1e1r; 1e1ri'
      message = 'expected a newline or semicolon after the statement'
      assert_errors expression(source), source, [
        [message, 3..3],
        [message, 9..9]
      ]
    end

    def test_check_value_expression
      source = <<~RUBY
        1 => ^(return)
        while true
          1 => ^(break)
          1 => ^(next)
          1 => ^(redo)
          1 => ^(retry)
          1 => ^(2 => a)
        end
        1 => ^(if 1; (return) else (return) end)
        1 => ^(unless 1; (return) else (return) end)
      RUBY
      message = 'unexpected void value expression'
      assert_errors expression(source), source, [
        [message, 7..13],
        [message, 35..40],
        [message, 51..55],
        [message, 66..70],
        [message, 81..86],
        [message, 97..103],
        [message, 123..129],
        [message, 168..174],
      ], compare_ripper: false # Ripper does not check 'void value expression'.
    end

    def test_void_value_expression_in_statement
      source = <<~RUBY
        if (return)
        end
        unless (return)
        end
        while (return)
        end
        until (return)
        end
        case (return)
        when 1
        end
        class A < (return)
        end
        class << (return)
        end
        for x in (return)
        end
      RUBY
      message = 'unexpected void value expression'
      assert_errors expression(source), source, [
        [message, 4..10],
        [message, 24..30],
        [message, 43..49],
        [message, 62..68],
        [message, 80..86],
        [message, 110..116],
        [message, 132..138],
        [message, 154..160],
      ], compare_ripper: false # Ripper does not check 'void value expression'.
    end

    def test_void_value_expression_in_def
      source = <<~RUBY
        def (return).x
        end
        def x(a = return)
        end
        def x(a: return)
        end
      RUBY
      message = 'unexpected void value expression'
      assert_errors expression(source), source, [
        [message, 5..11],
        [message, 29..35],
        [message, 50..56],
      ], compare_ripper: false # Ripper does not check 'void value expression'.
    end

    def test_void_value_expression_in_assignment
      source = <<~RUBY
        a = return
        a = 1, return
        a, b = return, 1
        a, b = 1, *return
      RUBY
      message = 'unexpected void value expression'
      assert_errors expression(source), source, [
        [message, 4..10],
        [message, 18..24],
        [message, 32..38],
        [message, 53..59],
      ], compare_ripper: false # Ripper does not check 'void value expression'.
    end

    def test_void_value_expression_in_modifier
      source = <<~RUBY
        1 if (return)
        1 unless (return)
        1 while (return)
        1 until (return)
        (return) => a
        (return) in a
      RUBY
      message = 'unexpected void value expression'
      assert_errors expression(source), source, [
        [message, 6..12],
        [message, 24..30],
        [message, 41..47],
        [message, 58..64],
        [message, 67..73],
        [message, 81..87]
      ], compare_ripper: false # Ripper does not check 'void value expression'.
    end

    def test_void_value_expression_in_expression
      source = <<~RUBY
        (return) ? 1 : 1
        (return)..1
        1..(return)
        (return)...1
        1...(return)
        (..(return))
        (...(return))
        ((return)..)
        ((return)...)
      RUBY
      message = 'unexpected void value expression'
      assert_errors expression(source), source, [
        [message, 1..7],
        [message, 18..24],
        [message, 33..39],
        [message, 42..48],
        [message, 59..65],
        [message, 71..77],
        [message, 85..91],
        [message, 96..102],
        [message, 109..115]
      ], compare_ripper: false # Ripper does not check 'void value expression'.
    end

    def test_void_value_expression_in_array
      source = <<~RUBY
        [return]
        [1, return]
        [ return => 1 ]
        [ 1 => return ]
        [ a: return ]
        [ *return ]
        [ **return ]
      RUBY
      message = 'unexpected void value expression'
      assert_errors expression(source), source, [
        [message, 1..7],
        [message, 13..19],
        [message, 23..29],
        [message, 44..50],
        [message, 58..64],
        [message, 70..76],
        [message, 83..89],
      ], compare_ripper: false # Ripper does not check 'void value expression'.
    end

    def test_void_value_expression_in_hash
      source = <<~RUBY
        { return => 1 }
        { 1 => return }
        { a: return }
        { **return }
      RUBY
      message = 'unexpected void value expression'
      assert_errors expression(source), source, [
        [message, 2..8],
        [message, 23..29],
        [message, 37..43],
        [message, 50..56],
      ], compare_ripper: false # Ripper does not check 'void value expression'.
    end

    def test_void_value_expression_in_call
      source = <<~RUBY
        (return).foo
        (return).(1)
        (return)[1]
        (return)[1] = 2
        (return)::foo
      RUBY
      message = 'unexpected void value expression'
      assert_errors expression(source), source, [
        [message, 1..7],
        [message, 14..20],
        [message, 27..33],
        [message, 39..45],
        [message, 55..61],
      ], compare_ripper: false # Ripper does not check 'void value expression'.
    end

    def test_void_value_expression_in_constant_path
      source = <<~RUBY
        (return)::A
        class (return)::A; end
      RUBY
      message = 'unexpected void value expression'
      assert_errors expression(source), source, [
        [message, 1..7],
        [message, 19..25],
      ], compare_ripper: false # Ripper does not check 'void value expression'.
    end

    def test_void_value_expression_in_arguments
      source = <<~RUBY
        foo(return)
        foo(1, return)
        foo(*return)
        foo(**return)
        foo(&return)
        foo(return => 1)
        foo(:a => return)
        foo(a: return)
      RUBY
      message = 'unexpected void value expression'
      assert_errors expression(source), source, [
        [message, 4..10],
        [message, 19..25],
        [message, 32..38],
        [message, 46..52],
        [message, 59..65],
        [message, 71..77],
        [message, 94..100],
        [message, 109..115],
      ], compare_ripper: false # Ripper does not check 'void value expression'.
    end

    def test_void_value_expression_in_unary_call
      source = <<~RUBY
        +(return)
        not return
      RUBY
      message = 'unexpected void value expression'
      assert_errors expression(source), source, [
        [message, 2..8],
        [message, 14..20],
      ], compare_ripper: false # Ripper does not check 'void value expression'.
    end

    def test_void_value_expression_in_binary_call
      source = <<~RUBY
        1 + (return)
        (return) + 1
        1 and (return)
        (return) and 1
        1 or (return)
        (return) or 1
      RUBY
      message = 'unexpected void value expression'
      assert_errors expression(source), source, [
        [message, 5..11],
        [message, 14..20],
        [message, 42..48],
        [message, 71..77],
      ], compare_ripper: false # Ripper does not check 'void value expression'.
    end

    def test_trailing_comma_in_calls
      assert_errors expression("foo 1,"), "foo 1,", [
        ["expected an argument", 5..6]
      ]
    end

    def test_argument_after_ellipsis
      source = 'def foo(...); foo(..., 1); end'
      assert_errors expression(source), source, [
        ['unexpected argument after `...`', 23..24]
      ]
    end

    def test_ellipsis_in_no_paren_call
      source = 'def foo(...); foo 1, ...; end'
      assert_errors expression(source), source, [
        ['unexpected `...` in an non-parenthesized call', 21..24]
      ]
    end

    def test_non_assoc_range
      source = '1....2'
      assert_errors expression(source), source, [
        ['expected a newline or semicolon after the statement', 4..4],
        ['cannot parse the expression', 4..4],
      ]
    end

    def test_upcase_end_in_def
      assert_warning_messages "def foo; END { }; end", [
        "END in method; use at_exit"
      ]
    end

    def test_statement_operators
      source = <<~RUBY
        alias x y + 1
        alias x y.z
        BEGIN { bar } + 1
        BEGIN { bar }.z
        END { bar } + 1
        END { bar }.z
        undef x + 1
        undef x.z
      RUBY
      message1 = 'expected a newline or semicolon after the statement'
      message2 = 'cannot parse the expression'
      assert_errors expression(source), source, [
        [message1, 9..9],
        [message2, 9..9],
        [message1, 23..23],
        [message2, 23..23],
        [message1, 39..39],
        [message2, 39..39],
        [message1, 57..57],
        [message2, 57..57],
        [message1, 71..71],
        [message2, 71..71],
        [message1, 87..87],
        [message2, 87..87],
        [message1, 97..97],
        [message2, 97..97],
        [message1, 109..109],
        [message2, 109..109],
      ]
    end

    def test_statement_at_non_statement
      source = <<~RUBY
        foo(alias x y)
        foo(BEGIN { bar })
        foo(END { bar })
        foo(undef x)
      RUBY
      assert_errors expression(source), source, [
        ['unexpected an `alias` at a non-statement position', 4..9],
        ['unexpected a `BEGIN` at a non-statement position', 19..24],
        ['unexpected an `END` at a non-statement position', 38..41],
        ['unexpected an `undef` at a non-statement position', 55..60],
      ]
    end

    def test_binary_range_with_left_unary_range
      source = <<~RUBY
        ..1..
        ...1..
      RUBY
      message1 = 'expected a newline or semicolon after the statement'
      message2 =  'cannot parse the expression'
      assert_errors expression(source), source, [
        [message1, 3..3],
        [message2, 3..3],
        [message1, 10..10],
        [message2, 10..10],
      ]
    end

    def test_circular_param
      source = <<~RUBY
        def foo(bar = bar) = 42
        def foo(bar: bar) = 42
        proc { |foo = foo| }
        proc { |foo: foo| }
      RUBY
      message = 'parameter default value references itself'
      assert_errors expression(source), source, [
        [message, 14..17],
        [message, 37..40],
        [message, 61..64],
        [message, 81..84],
      ], compare_ripper: false # Ripper does not check 'circular reference'.
    end

    def test_command_calls
      sources = <<~RUBY.lines
        [a b]
        {a: b c}
        ...a b
        if ...a b; end
        a b, c d
        a(b, c d)
        a(*b c)
        a(**b c)
        a(&b c)
        +a b
        a + b c
        a && b c
        a =~ b c
        a = b, c d
        a = *b c
        a, b = c = d f
        a ? b c : d e
        defined? a b
        ! ! a b
        def f a = b c; end
        def f(a = b c); end
        a = b rescue c d
        def a = b rescue c d
        ->a=b c{}
        ->(a=b c){}
        case; when a b; end
        case; in a if a b; end
        case; in a unless a b; end
        begin; rescue a b; end
        begin; rescue a b => c; end
      RUBY
      sources.each do |source|
        assert_nil Ripper.sexp_raw(source)
        assert_false(Prism.parse(source).success?)
      end
    end

    def test_range_and_bin_op
      sources = <<~RUBY.lines
        1..2..3
        1..2..
        1.. || 2
        1.. & 2
        1.. * 2
        1.. / 2
        1.. % 2
        1.. ** 2
      RUBY
      sources.each do |source|
        assert_nil Ripper.sexp_raw(source)
        assert_false(Prism.parse(source).success?)
      end
    end

    def test_constant_assignment_in_method
      source = 'def foo();A=1;end'
      assert_errors expression(source), source, [
        ['dynamic constant assignment', 10..13]
      ]
    end

    def test_non_assoc_equality
      source = <<~RUBY
        1 == 2 == 3
        1 != 2 != 3
        1 === 2 === 3
        1 =~ 2 =~ 3
        1 !~ 2 !~ 3
        1 <=> 2 <=> 3
      RUBY
      message1 = 'expected a newline or semicolon after the statement'
      message2 = 'cannot parse the expression'
      assert_errors expression(source), source, [
        [message1, 6..6],
        [message2, 6..6],
        [message1, 18..18],
        [message2, 18..18],
        [message1, 31..31],
        [message2, 31..31],
        [message1, 44..44],
        [message2, 44..44],
        [message1, 56..56],
        [message2, 56..56],
        [message1, 69..69],
        [message2, 69..69],
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

    def assert_warning_messages(source, warnings)
      result = Prism.parse(source)
      assert_equal(warnings, result.warnings.map(&:message))
    end

    def expression(source)
      Prism.parse(source).value.statements.body.last
    end
  end
end
