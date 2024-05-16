# frozen_string_literal: true

require_relative "test_helper"

module Prism
  class ErrorsTest < TestCase
    include DSL

    def test_constant_path_with_invalid_token_after
      assert_error_messages "A::$b", [
        "expected a constant after the `::` operator",
        "unexpected global variable, expecting end-of-input"
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
        ["unexpected constant path after `module`; class/module name must be CONSTANT", 14..20],
        ["unexpected 'end', assuming it is closing the parent module definition", 21..24]
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
        ["unexpected '}'; expected an expression after the operator", 12..13],
        ["unexpected '}', assuming it is closing the parent 'BEGIN' block", 12..13]
      ]
    end

    def test_unterminated_embdoc
      message = "embedded document meets end of file"
      assert_error_messages "=begin", [message]
      assert_error_messages "=begin\n", [message]

      refute_error_messages "=begin\n=end"
      refute_error_messages "=begin\n=end\0"
      refute_error_messages "=begin\n=end\C-d"
      refute_error_messages "=begin\n=end\C-z"
    end

    def test_unterminated_i_list
      assert_errors expression("%i["), "%i[", [
        ["unterminated list; expected a closing delimiter for the `%i`", 0..3]
      ]
    end

    def test_unterminated_w_list
      assert_errors expression("%w["), "%w[", [
        ["unterminated list; expected a closing delimiter for the `%w`", 0..3]
      ]
    end

    def test_unterminated_W_list
      assert_errors expression("%W["), "%W[", [
        ["unterminated list; expected a closing delimiter for the `%W`", 0..3]
      ]
    end

    def test_unterminated_regular_expression
      assert_errors expression("/hello"), "/hello", [
        ["unterminated regexp meets end of file; expected a closing delimiter", 0..1]
      ]
    end

    def test_unterminated_regular_expression_with_heredoc
      source = "<<-END + /b\nEND\n"

      assert_errors expression(source), source, [
        ["unterminated regexp meets end of file; expected a closing delimiter", 9..10]
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
        ["unterminated string meets end of file", 6..6]
      ]
      assert_equal expr.unescaped, "hello"
      assert_equal expr.closing, ""
    end

    def test_unterminated_string
      expr = expression("'hello")
      assert_errors expr, "'hello", [
        ["unterminated string meets end of file", 0..1]
      ]
      assert_equal expr.unescaped, "hello"
      assert_equal expr.closing, ""
    end

    def test_unterminated_empty_string
      expr = expression('"')
      assert_errors expr, '"', [
        ["unterminated string meets end of file", 1..1]
      ]
      assert_equal expr.unescaped, ""
      assert_equal expr.closing, ""
    end

    def test_incomplete_instance_var_string
      assert_errors expression('%@#@@#'), '%@#@@#', [
        ["'@' without identifiers is not allowed as an instance variable name", 4..5],
        ["unexpected instance variable, expecting end-of-input", 4..5]
      ]
    end

    def test_unterminated_s_symbol
      assert_errors expression("%s[abc"), "%s[abc", [
        ["unterminated quoted string; expected a closing delimiter for the dynamic symbol", 0..3]
      ]
    end

    def test_unterminated_parenthesized_expression
      assert_errors expression('(1 + 2'), '(1 + 2', [
        ["unexpected end-of-input, assuming it is closing the parent top level context", 6..6],
        ["expected a matching `)`", 6..6]
      ]
    end

    def test_missing_terminator_in_parentheses
      assert_error_messages "(0 0)", [
        "unexpected integer, expecting end-of-input"
      ]
    end

    def test_unterminated_argument_expression
      assert_errors expression('a %'), 'a %', [
        ["invalid `%` token", 2..3],
        ["unexpected end-of-input; expected an expression after the operator", 3..3],
        ["unexpected end-of-input, assuming it is closing the parent top level context", 3..3]
      ]
    end

    def test_unterminated_interpolated_symbol
      assert_error_messages ":\"#", [
        "expected a closing delimiter for the interpolated symbol"
      ]
    end

    def test_cr_without_lf_in_percent_expression
      assert_errors expression("%\r"), "%\r", [
        ["unterminated string meets end of file", 2..2],
      ]
    end

    def test_1_2_3
      assert_errors expression("(1, 2, 3)"), "(1, 2, 3)", [
        ["unexpected ',', expecting end-of-input", 2..3],
        ["unexpected ',', ignoring it", 2..3],
        ["expected a matching `)`", 2..2],
        ["unexpected ',', expecting end-of-input", 2..3],
        ["unexpected ',', ignoring it", 2..3],
        ["unexpected ',', expecting end-of-input", 5..6],
        ["unexpected ',', ignoring it", 5..6],
        ["unexpected ')', expecting end-of-input", 8..9],
        ["unexpected ')', ignoring it", 8..9]
      ]
    end

    def test_return_1_2_3
      assert_error_messages "return(1, 2, 3)", [
        "unexpected ',', expecting end-of-input",
        "unexpected ',', ignoring it",
        "expected a matching `)`",
        "unexpected ')', expecting end-of-input",
        "unexpected ')', ignoring it"
      ]
    end

    def test_return_1
      assert_errors expression("return 1,;"), "return 1,;", [
        ["expected an argument", 8..9]
      ]
    end

    def test_next_1_2_3
      assert_errors expression("next(1, 2, 3)"), "next(1, 2, 3)", [
        ["unexpected ',', expecting end-of-input", 6..7],
        ["unexpected ',', ignoring it", 6..7],
        ["expected a matching `)`", 6..6],
        ["Invalid next", 0..12],
        ["unexpected ')', expecting end-of-input", 12..13],
        ["unexpected ')', ignoring it", 12..13]
      ]
    end

    def test_next_1
      assert_errors expression("next 1,;"), "next 1,;", [
        ["expected an argument", 6..7],
        ["Invalid next", 0..7]
      ]
    end

    def test_break_1_2_3
      assert_errors expression("break(1, 2, 3)"), "break(1, 2, 3)", [
        ["unexpected ',', expecting end-of-input", 7..8],
        ["unexpected ',', ignoring it", 7..8],
        ["expected a matching `)`", 7..7],
        ["Invalid break", 0..13],
        ["unexpected ')', expecting end-of-input", 13..14],
        ["unexpected ')', ignoring it", 13..14]
      ]
    end

    def test_break_1
      assert_errors expression("break 1,;"), "break 1,;", [
        ["expected an argument", 7..8],
        ["Invalid break", 0..8]
      ]
    end

    def test_argument_forwarding_when_parent_is_not_forwarding
      assert_errors expression('def a(x, y, z); b(...); end'), 'def a(x, y, z); b(...); end', [
        ["unexpected ... when the parent method is not forwarding", 18..21]
      ]
    end

    def test_argument_forwarding_only_effects_its_own_internals
      assert_errors expression('def a(...); b(...); end; def c(x, y, z); b(...); end'),
        'def a(...); b(...); end; def c(x, y, z); b(...); end', [
          ["unexpected ... when the parent method is not forwarding", 43..46]
        ]
    end

    def test_top_level_constant_with_downcased_identifier
      assert_error_messages "::foo", [
        "expected a constant after the `::` operator",
        "unexpected local variable or method, expecting end-of-input"
      ]
    end

    def test_top_level_constant_starting_with_downcased_identifier
      assert_error_messages "::foo::A", [
        "expected a constant after the `::` operator",
        "unexpected local variable or method, expecting end-of-input"
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
        ["invalid argument being passed to `alias`; can't make alias for the number variables", 9..11]
      ]
    end

    def test_def_with_expression_receiver_and_no_identifier
      assert_errors expression("def (a); end"), "def (a); end", [
        ["expected a `.` or `::` after the receiver in a method definition", 7..7],
        ["unexpected ';'; expected a method name", 7..8]
      ]
    end

    def test_def_with_multiple_statements_receiver
      assert_errors expression("def (\na\nb\n).c; end"), "def (\na\nb\n).c; end", [
        ["expected a matching `)`", 8..8],
        ["expected a `.` or `::` after the receiver in a method definition", 8..8],
        ["expected a delimiter to close the parameters", 9..9],
        ["unexpected ')', ignoring it", 10..11],
        ["unexpected '.', ignoring it", 11..12]
      ]
    end

    def test_def_with_empty_expression_receiver
      assert_errors expression("def ().a; end"), "def ().a; end", [
        ["expected a receiver for the method definition", 4..5]
      ]
    end

    def test_block_beginning_with_brace_and_ending_with_end
      assert_error_messages "x.each { x end", [
        "unexpected 'end', expecting end-of-input",
        "unexpected 'end', ignoring it",
        "unexpected end-of-input, assuming it is closing the parent top level context",
        "expected a block beginning with `{` to end with `}`"
      ]
    end

    def test_double_splat_followed_by_splat_argument
      expected = CallNode(
        CallNodeFlags::IGNORE_VISIBILITY,
        nil,
        nil,
        :a,
        Location(),
        Location(),
        ArgumentsNode(
          ArgumentsNodeFlags::CONTAINS_KEYWORDS | ArgumentsNodeFlags::CONTAINS_KEYWORD_SPLAT,
          [
            KeywordHashNode(0, [AssocSplatNode(expression("kwargs"), Location())]),
            SplatNode(Location(), expression("args"))
          ]
        ),
        Location(),
        nil
      )

      assert_errors expected, "a(**kwargs, *args)", [
        ["unexpected `*` splat argument after a `**` keyword splat argument", 12..17]
      ]
    end

    def test_arguments_after_block
      expected = CallNode(
        CallNodeFlags::IGNORE_VISIBILITY,
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
        "unexpected 'and'; expected a `)` to close the arguments",
        "unexpected ')', expecting end-of-input",
        "unexpected ')', ignoring it"
      ]
    end

    def test_splat_argument_after_keyword_argument
      expected = CallNode(
        CallNodeFlags::IGNORE_VISIBILITY,
        nil,
        nil,
        :a,
        Location(),
        Location(),
        ArgumentsNode(ArgumentsNodeFlags::CONTAINS_KEYWORDS, [
          KeywordHashNode(1, [
            AssocNode(
              SymbolNode(SymbolFlags::FORCED_US_ASCII_ENCODING, nil, Location(), Location(), "foo"),
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
        Location(),
        nil,
        nil,
        nil,
        nil,
        Location()
      )

      assert_errors expected, "def foo;module A;end;end", [
        ["unexpected module definition in method body", 8..14]
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
            CallNodeFlags::IGNORE_VISIBILITY,
            nil,
            nil,
            :bar,
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
            )
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

      assert_errors expected, <<~RUBY, [["unexpected module definition in method body", 21..27]]
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
      message = "unexpected module definition in method body"
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
        Location(),
        nil,
        nil,
        nil,
        nil,
        Location()
      )

      assert_errors expected, "def foo;class A;end;end", [
        ["unexpected class definition in method body", 8..13]
      ]
    end

    def test_class_definition_in_method_defs
      source = <<~RUBY
        def foo(bar = class A;end);end
        def foo;rescue;class A;end;end
        def foo;ensure;class A;end;end
      RUBY
      message = "unexpected class definition in method body"
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
          RequiredParameterNode(0, :A),
          RequiredParameterNode(0, :@a),
          RequiredParameterNode(0, :$A),
          RequiredParameterNode(0, :@@a),
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
        ["invalid formal argument; formal argument cannot be a constant", 8..9],
        ["invalid formal argument; formal argument cannot be an instance variable", 11..13],
        ["invalid formal argument; formal argument cannot be a global variable", 15..17],
        ["invalid formal argument; formal argument cannot be a class variable", 19..22],
      ]
    end

    if RUBY_VERSION >= "3.0"
      def test_cannot_assign_to_a_reserved_numbered_parameter
        expected = BeginNode(
          Location(),
          StatementsNode([
            LocalVariableWriteNode(:_1, 0, Location(), SymbolNode(SymbolFlags::FORCED_US_ASCII_ENCODING, Location(), Location(), nil, "a"), Location()),
            LocalVariableWriteNode(:_2, 0, Location(), SymbolNode(SymbolFlags::FORCED_US_ASCII_ENCODING, Location(), Location(), nil, "a"), Location()),
            LocalVariableWriteNode(:_3, 0, Location(), SymbolNode(SymbolFlags::FORCED_US_ASCII_ENCODING, Location(), Location(), nil, "a"), Location()),
            LocalVariableWriteNode(:_4, 0, Location(), SymbolNode(SymbolFlags::FORCED_US_ASCII_ENCODING, Location(), Location(), nil, "a"), Location()),
            LocalVariableWriteNode(:_5, 0, Location(), SymbolNode(SymbolFlags::FORCED_US_ASCII_ENCODING, Location(), Location(), nil, "a"), Location()),
            LocalVariableWriteNode(:_6, 0, Location(), SymbolNode(SymbolFlags::FORCED_US_ASCII_ENCODING, Location(), Location(), nil, "a"), Location()),
            LocalVariableWriteNode(:_7, 0, Location(), SymbolNode(SymbolFlags::FORCED_US_ASCII_ENCODING, Location(), Location(), nil, "a"), Location()),
            LocalVariableWriteNode(:_8, 0, Location(), SymbolNode(SymbolFlags::FORCED_US_ASCII_ENCODING, Location(), Location(), nil, "a"), Location()),
            LocalVariableWriteNode(:_9, 0, Location(), SymbolNode(SymbolFlags::FORCED_US_ASCII_ENCODING, Location(), Location(), nil, "a"), Location()),
            LocalVariableWriteNode(:_10, 0, Location(), SymbolNode(SymbolFlags::FORCED_US_ASCII_ENCODING, Location(), Location(), nil, "a"), Location())
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
    end

    def test_do_not_allow_trailing_commas_in_method_parameters
      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode(
          [RequiredParameterNode(0, :a), RequiredParameterNode(0, :b), RequiredParameterNode(0, :c)],
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
        ["unexpected `,` in parameters", 13..14]
      ]
    end

    def test_do_not_allow_trailing_commas_in_lambda_parameters
      expected = LambdaNode(
        [:a, :b],
        Location(),
        Location(),
        Location(),
        BlockParametersNode(
          ParametersNode([RequiredParameterNode(0, :a), RequiredParameterNode(0, :b)], [], nil, [], [], nil, nil),
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
        ["invalid Unicode escape sequence; Multiple codepoints at single character literal are disallowed", 9..12]
      ]
    end

    def test_invalid_hex_escape
      assert_errors expression('"\\xx"'), '"\\xx"', [
        ["invalid hex escape sequence", 1..3],
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
          [RequiredParameterNode(0, :a)],
          [],
          nil,
          BlockParameterNode(0, :block, Location(), Location())
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
        ["unexpected parameter order", 16..17]
      ]
    end

    def test_method_with_arguments_after_anonymous_block
      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([], [], nil, [RequiredParameterNode(0, :a)], [], nil, BlockParameterNode(0, nil, nil, Location())),
        nil,
        [:a],
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
          [RequiredParameterNode(0, :a)],
          [],
          ForwardingParameterNode(),
          nil
        ),
        nil,
        [:a],
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
          [RequiredParameterNode(0, :a)],
          [RequiredKeywordParameterNode(0, :b, Location())],
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
          [RequiredKeywordParameterNode(0, :b, Location())],
          KeywordRestParameterNode(0, :rest, Location(), Location()),
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
        ["unexpected parameter order", 16..18]
      ]
    end

    def test_double_arguments_forwarding
      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([], [], nil, [ForwardingParameterNode()], [], ForwardingParameterNode(), nil),
        nil,
        [],
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
          [RequiredParameterNode(0, :a)],
          [RequiredKeywordParameterNode(0, :b, Location())],
          KeywordRestParameterNode(0, :args, Location(), Location()),
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
          [RequiredParameterNode(0, :a)],
          [RequiredKeywordParameterNode(0, :b, Location())],
          KeywordRestParameterNode(0, :args, Location(), Location()),
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
          [RequiredParameterNode(0, :a)],
          [RequiredKeywordParameterNode(0, :b, Location())],
          KeywordRestParameterNode(0, :args, Location(), Location()),
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
          [RequiredParameterNode(0, :a)],
          [
            OptionalParameterNode(0, :b, Location(), Location(), IntegerNode(IntegerBaseFlags::DECIMAL, 1)),
            OptionalParameterNode(0, :d, Location(), Location(), IntegerNode(IntegerBaseFlags::DECIMAL, 2))
          ],
          nil,
          [RequiredParameterNode(0, :c), RequiredParameterNode(0, :e)],
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
        ["unexpected parameter order", 23..24]
      ]
    end

    def test_case_without_when_clauses_errors_on_else_clause
      expected = CaseMatchNode(
        SymbolNode(SymbolFlags::FORCED_US_ASCII_ENCODING, Location(), Location(), nil, "a"),
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
        SymbolNode(SymbolFlags::FORCED_US_ASCII_ENCODING, Location(), Location(), nil, "a"),
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
        StatementsNode([IntegerNode(IntegerBaseFlags::DECIMAL, 42)]),
        [],
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
        Location(),
        Location(),
        Location(),
        BlockParametersNode(ParametersNode([], [], nil, [], [], ForwardingParameterNode(), nil), [], Location(), Location()),
        nil
      )

      assert_errors expected, "->(...) {}", [
        ["unexpected ... when the parent method is not forwarding", 3..6]
      ]
    end

    def test_do_not_allow_forward_arguments_in_blocks
      expected = CallNode(
        CallNodeFlags::IGNORE_VISIBILITY,
        nil,
        nil,
        :a,
        Location(),
        nil,
        nil,
        nil,
        BlockNode(
          [],
          BlockParametersNode(ParametersNode([], [], nil, [], [], ForwardingParameterNode(), nil), [], Location(), Location()),
          nil,
          Location(),
          Location()
        )
      )

      assert_errors expected, "a {|...|}", [
        ["unexpected ... when the parent method is not forwarding", 4..7]
      ]
    end

    def test_dont_allow_return_inside_class_body
      expected = ClassNode(
        [],
        Location(),
        ConstantReadNode(:A),
        nil,
        nil,
        StatementsNode([ReturnNode(0, Location(), nil)]),
        Location(),
        :A
      )

      assert_errors expected, "class A; return; end", [
        ["Invalid return in class/module body", 9..15]
      ]
    end

    def test_dont_allow_return_inside_module_body
      expected = ModuleNode(
        [],
        Location(),
        ConstantReadNode(:A),
        StatementsNode([ReturnNode(0, Location(), nil)]),
        Location(),
        :A
      )

      assert_errors expected, "module A; return; end", [
        ["Invalid return in class/module body", 10..16]
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
        ["Can't set variable $+", 6..8],
        ["Can't set variable $1466", 15..20]
      ]
    end

    def test_duplicated_parameter_names
      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([RequiredParameterNode(0, :a), RequiredParameterNode(0, :b), RequiredParameterNode(ParameterFlags::REPEATED_PARAMETER, :a)], [], nil, [], [], nil, nil),
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
        ["duplicated argument name", 12..13]
      ]

      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([RequiredParameterNode(0, :a), RequiredParameterNode(0, :b)], [], RestParameterNode(ParameterFlags::REPEATED_PARAMETER, :a, Location(), Location()), [], [], nil, nil),
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
        ["duplicated argument name", 13..14]
      ]

      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([RequiredParameterNode(0, :a), RequiredParameterNode(0, :b)], [], nil, [], [], KeywordRestParameterNode(ParameterFlags::REPEATED_PARAMETER, :a, Location(), Location()), nil),
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
        ["duplicated argument name", 14..15]
      ]

      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([RequiredParameterNode(0, :a), RequiredParameterNode(0, :b)], [], nil, [], [], nil, BlockParameterNode(ParameterFlags::REPEATED_PARAMETER, :a, Location(), Location())),
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
        ["duplicated argument name", 13..14]
      ]

      expected = DefNode(
        :foo,
        Location(),
        nil,
        ParametersNode([], [OptionalParameterNode(0, :a, Location(), Location(), IntegerNode(IntegerBaseFlags::DECIMAL, 1))], RestParameterNode(0, :c, Location(), Location()), [RequiredParameterNode(0, :b)], [], nil, nil),
        nil,
        [:a, :b, :c],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(a = 1,b,*c);end", [["unexpected parameter `*`", 16..17]]
    end

    def test_content_after_unterminated_heredoc
      receiver = StringNode(0, Location(), Location(), Location(), "")
      expected = CallNode(0, receiver, Location(), :foo, Location(), nil, nil, nil, nil)

      assert_errors expected, "<<~FOO.foo\n", [
        ["unterminated heredoc; can't find string \"FOO\" anywhere before EOF", 3..6]
      ]
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
      message = "'$' without identifiers is not allowed as a global variable name"

      assert_errors expression("$"), "$", [[message, 0..1]]
      assert_errors expression("$ "), "$ ", [[message, 0..1]]
    end

    def test_invalid_global_variable_write
      assert_errors expression("$',"), "$',", [
        ["Can't set variable $'", 0..2],
        ["unexpected write target", 0..2]
      ]
    end

    def test_invalid_multi_target
      error_messages = ["unexpected write target"]

      assert_error_messages "foo,", error_messages
      assert_error_messages "foo = 1; foo,", error_messages
      assert_error_messages "foo.bar,", error_messages
      assert_error_messages "*foo,", error_messages
      assert_error_messages "@foo,", error_messages
      assert_error_messages "@@foo,", error_messages
      assert_error_messages "$foo,", error_messages
      assert_error_messages "$1,", ["Can't set variable $1", *error_messages]
      assert_error_messages "$+,", ["Can't set variable $+", *error_messages]
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

    if RUBY_VERSION >= "3.0"
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
    end

    def test_double_scope_numbered_parameters
      source = "-> { _1 + -> { _2 } }"
      errors = [["numbered parameter is already used in outer scope", 15..17]]

      assert_errors expression(source), source, errors
    end

    def test_invalid_number_underscores
      error_messages = ["invalid underscore placement in number"]
      assert_error_messages "1__1", error_messages
      assert_error_messages "0b1__1", error_messages
      assert_error_messages "0o1__1", error_messages
      assert_error_messages "01__1", error_messages
      assert_error_messages "0d1__1", error_messages
      assert_error_messages "0x1__1", error_messages

      error_messages = ["trailing '_' in number"]
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

    if RUBY_VERSION >= "3.0"
      def test_numbered_parameters_in_block_arguments
        source = "foo { |_1| }"
        assert_errors expression(source), source, [
          ["_1 is reserved for numbered parameters", 7..9],
        ]
      end
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
      assert_errors expression(source), source, errors
    end

    def test_class_name
      source = "class 0.X end"
      assert_errors expression(source), source, [
        ["unexpected constant path after `class`; class/module name must be CONSTANT", 6..9],
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
        ["unexpected parameter order", 9..12]
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
        ["unexpected end-of-input, assuming it is closing the parent top level context", 7..7],
        ["expected a lambda block beginning with `do` to end with `end`", 7..7]
      ]
    end

    def test_shadow_args_in_block
      source = "tap{|a;a|}"
      assert_errors expression(source), source, [
        ["duplicated argument name", 7..8],
      ]
    end

    def test_repeated_parameter_name_in_destructured_params
      source = "def f(a, (b, (a))); end"

      assert_errors expression(source), source, [
        ["duplicated argument name", 14..15],
      ]
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
        ["unexpected label terminator, expected a string literal terminator", 12..14]
      ]
    end

    def test_symbol_in_hash
      source = "{x:'y':}"
      assert_errors expression(source), source, [
        ["unexpected label terminator, expected a string literal terminator", 5..7]
      ]
    end

    def test_while_endless_method
      source = "while def f = g do end"

      assert_errors expression(source), source, [
        ["expected a predicate expression for the `while` statement", 22..22],
        ["unexpected end-of-input, assuming it is closing the parent top level context", 22..22],
        ["expected an `end` to close the `while` statement", 22..22]
      ]
    end

    def test_match_plus
      source = <<~RUBY
        a in b + c
        a => b + c
      RUBY

      assert_errors expression(source), source, [
        ["unexpected '+', expecting end-of-input", 7..8],
        ["unexpected '+', ignoring it", 7..8],
        ["unexpected '+', expecting end-of-input", 18..19],
        ["unexpected '+', ignoring it", 18..19]
      ]
    end

    def test_rational_number_with_exponential_portion
      source = '1e1r; 1e1ri'

      assert_errors expression(source), source, [
        ["unexpected local variable or method, expecting end-of-input", 3..4],
        ["unexpected local variable or method, expecting end-of-input", 9..11]
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

      message = "unexpected void value expression"
      assert_errors expression(source), source, [
        [message, 7..13],
        [message, 35..40],
        [message, 51..55],
        [message, 66..70],
        ["Invalid retry without rescue", 81..86],
        [message, 81..86],
        [message, 97..103],
        [message, 123..129],
        [message, 168..174],
      ]
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
      ]
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
      ]
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
      ]
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
      ]
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
      ]
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
      ]
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
      ]
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
      ]
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
      ]
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
      ]
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
      ]
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
      ]
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
        ["unexpected '.', expecting end-of-input", 4..5],
        ["unexpected '.', ignoring it", 4..5]
      ]
    end

    def test_upcase_end_in_def
      assert_warning_messages "def foo; END { }; end", [
        "END in method; use at_exit"
      ]
    end

    def test_warnings_verbosity
      warning = Prism.parse("def foo; END { }; end").warnings[0]
      assert_equal "END in method; use at_exit", warning.message
      assert_equal :default, warning.level

      warning = Prism.parse("foo /regexp/").warnings[0]
      assert_equal "ambiguous `/`; wrap regexp in parentheses or add a space after `/` operator", warning.message
      assert_equal :verbose, warning.level
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

      assert_errors expression(source), source, [
        ["unexpected '+', expecting end-of-input", 10..11],
        ["unexpected '+', ignoring it", 10..11],
        ["unexpected '.', expecting end-of-input", 23..24],
        ["unexpected '.', ignoring it", 23..24],
        ["unexpected '+', expecting end-of-input", 40..41],
        ["unexpected '+', ignoring it", 40..41],
        ["unexpected '.', expecting end-of-input", 57..58],
        ["unexpected '.', ignoring it", 57..58],
        ["unexpected '+', expecting end-of-input", 72..73],
        ["unexpected '+', ignoring it", 72..73],
        ["unexpected '.', expecting end-of-input", 87..88],
        ["unexpected '.', ignoring it", 87..88],
        ["unexpected '+', expecting end-of-input", 98..99],
        ["unexpected '+', ignoring it", 98..99],
        ["unexpected '.', expecting end-of-input", 109..110],
        ["unexpected '.', ignoring it", 109..110]
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

      assert_errors expression(source), source, [
        ["unexpected .., expecting end-of-input", 3..5],
        ["unexpected .., ignoring it", 3..5],
        ["unexpected .., expecting end-of-input", 10..12],
        ["unexpected .., ignoring it", 10..12]
      ]
    end

    def test_circular_param
      source = <<~RUBY
        def foo(bar = bar) = 42
        def foo(bar: bar) = 42
        proc { |foo = foo| }
        proc { |foo: foo| }
      RUBY

      assert_errors expression(source), source, [
        ["circular argument reference - bar", 8..11],
        ["circular argument reference - bar", 32..35],
        ["circular argument reference - foo", 55..58],
        ["circular argument reference - foo", 76..79]
      ]

      refute_error_messages("def foo(bar: bar = 1); end")
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
        refute_valid_syntax(source)
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
        refute_valid_syntax(source)
        assert_false(Prism.parse(source).success?)
      end
    end

    def test_command_call_in
      source = <<~RUBY
        foo 1 in a
        a = foo 2 in b
      RUBY

      assert_errors expression(source), source, [
        ["unexpected `in` keyword in arguments", 9..10],
        ["unexpected local variable or method, expecting end-of-input", 9..10],
        ["unexpected `in` keyword in arguments", 24..25],
        ["unexpected local variable or method, expecting end-of-input", 24..25]
      ]
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

      assert_errors expression(source), source, [
        ["unexpected '==', expecting end-of-input", 7..9],
        ["unexpected '==', ignoring it", 7..9],
        ["unexpected '!=', expecting end-of-input", 19..21],
        ["unexpected '!=', ignoring it", 19..21],
        ["unexpected '===', expecting end-of-input", 32..35],
        ["unexpected '===', ignoring it", 32..35],
        ["unexpected '=~', expecting end-of-input", 45..47],
        ["unexpected '=~', ignoring it", 45..47],
        ["unexpected '!~', expecting end-of-input", 57..59],
        ["unexpected '!~', ignoring it", 57..59],
        ["unexpected '<=>', expecting end-of-input", 70..73],
        ["unexpected '<=>', ignoring it", 70..73]
      ]
    end

    def test_block_arg_and_block
      source = 'foo(&1) { }'
      assert_errors expression(source), source, [
        ["both block arg and actual block given; only one block is allowed", 8..11]
      ]
    end

    def test_forwarding_arg_and_block
      source = 'def foo(...) = foo(...) { }'
      assert_errors expression(source), source, [
        ['both block arg and actual block given; only one block is allowed', 24..27]
      ]
    end

    def test_it_with_ordinary_parameter
      source = "proc { || it }"
      errors = [["`it` is not allowed when an ordinary parameter is defined", 10..12]]

      assert_errors expression(source), source, errors, check_valid_syntax: RUBY_VERSION >= "3.4.0"
    end

    def test_regular_expression_with_unknown_regexp_options
      source = "/foo/AZaz"
      errors = [["unknown regexp options: AZaz", 4..9]]

      assert_errors expression(source), source, errors
    end

    def test_interpolated_regular_expression_with_unknown_regexp_options
      source = "/\#{foo}/AZaz"
      errors = [["unknown regexp options: AZaz", 7..12]]

      assert_errors expression(source), source, errors
    end

    def test_singleton_method_for_literals
      source = <<~'RUBY'
        def (1).g; end
        def ((a; 1)).foo; end
        def ((return; 1)).bar; end
        def (((1))).foo; end
        def (__FILE__).foo; end
        def (__ENCODING__).foo; end
        def (__LINE__).foo; end
        def ("foo").foo; end
        def (3.14).foo; end
        def (3.14i).foo; end
        def (:foo).foo; end
        def (:'foo').foo; end
        def (:'f{o}').foo; end
        def ('foo').foo; end
        def ("foo").foo; end
        def ("#{fo}o").foo; end
        def (/foo/).foo; end
        def (/f#{oo}/).foo; end
        def ([1]).foo; end
      RUBY
      errors = [
        ["cannot define singleton method for literals", 5..6],
        ["cannot define singleton method for literals", 24..25],
        ["cannot define singleton method for literals", 51..52],
        ["cannot define singleton method for literals", 71..72],
        ["cannot define singleton method for literals", 90..98],
        ["cannot define singleton method for literals", 114..126],
        ["cannot define singleton method for literals", 142..150],
        ["cannot define singleton method for literals", 166..171],
        ["cannot define singleton method for literals", 187..191],
        ["cannot define singleton method for literals", 207..212],
        ["cannot define singleton method for literals", 228..232],
        ["cannot define singleton method for literals", 248..254],
        ["cannot define singleton method for literals", 270..277],
        ["cannot define singleton method for literals", 293..298],
        ["cannot define singleton method for literals", 314..319],
        ["cannot define singleton method for literals", 335..343],
        ["cannot define singleton method for literals", 359..364],
        ["cannot define singleton method for literals", 380..388],
        ["cannot define singleton method for literals", 404..407]
      ]
      assert_errors expression(source), source, errors
    end

    def test_assignment_to_literal_in_conditionals
      source = <<~RUBY
        if (a = 2); end
        if ($a = 2); end
        if (@a = 2); end
        if (@@a = 2); end
        if a elsif b = 2; end
        unless (a = 2); end
        unless ($a = 2); end
        unless (@a = 2); end
        unless (@@a = 2); end
        while (a = 2); end
        while ($a = 2); end
        while (@a = 2); end
        while (@@a = 2); end
        until (a = 2); end
        until ($a = 2); end
        until (@a = 2); end
        until (@@a = 2); end
        foo if a = 2
        foo if (a, b = 2)
        (@foo = 1) ? a : b
        !(a = 2)
        not a = 2
      RUBY
      assert_warning_messages source, [
        "found '= literal' in conditional, should be =="
      ] * source.lines.count
    end

    def test_duplicate_pattern_capture
      source = <<~RUBY
        case (); in [a, a]; end
        case (); in [a, *a]; end
        case (); in {a: a, b: a}; end
        case (); in {a: a, **a}; end
        case (); in [a, {a:}]; end
        case (); in [a, {a: {a: {a: [a]}}}]; end
        case (); in a => a; end
        case (); in [A => a, {a: b => a}]; end
      RUBY

      assert_error_messages source, Array.new(source.lines.length, "duplicated variable name")
      refute_error_messages "case (); in [_a, _a]; end"
    end

    def test_duplicate_pattern_hash_key
      assert_error_messages "case (); in {a:, a:}; end", ["duplicated key name", "duplicated variable name"]
      assert_error_messages "case (); in {a:1, a:2}; end", ["duplicated key name"]
      refute_error_messages "case (); in [{a:1}, {a:2}]; end"
    end

    def test_unexpected_block
      assert_error_messages "def foo = yield(&:+)", ["block argument should not be given"]
    end

    private

    def assert_errors(expected, source, errors, check_valid_syntax: true)
      refute_valid_syntax(source) if check_valid_syntax

      result = Prism.parse(source)
      node = result.value.statements.body.last

      assert_equal_nodes(expected, node, compare_location: false)
      assert_equal(errors, result.errors.map { |e| [e.message, e.location.start_offset..e.location.end_offset] })
    end

    def assert_error_messages(source, errors)
      refute_valid_syntax(source)
      result = Prism.parse(source)
      assert_equal(errors, result.errors.map(&:message))
    end

    def refute_error_messages(source)
      assert_valid_syntax(source)
      assert Prism.parse_success?(source), "Expected #{source.inspect} to parse successfully"
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
