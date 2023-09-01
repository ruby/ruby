# frozen_string_literal: true

require_relative "test_helper"

module YARP
  class ErrorsTest < TestCase
    include DSL

    def test_constant_path_with_invalid_token_after
      assert_error_messages "A::$b", [
        "Expected identifier or constant after '::'",
        "Expected a newline or semicolon after statement."
      ]
    end

    def test_module_name_recoverable
      expected = ModuleNode(
        [],
        Location(),
        ConstantReadNode(),
        StatementsNode(
          [ModuleNode([], Location(), MissingNode(), nil, Location(), "")]
        ),
        Location(),
        "Parent"
      )

      assert_errors expected, "module Parent module end", [
        ["Expected to find a module name after `module`.", 20..20]
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
        ["Expected index after for.", 0..0]
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
        ["Expected index after for.", 0..0],
        ["Expected keyword in.", 3..3],
        ["Expected collection.", 3..3]
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
        ["Expected '{' after 'BEGIN'.", 5..5]
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
            "+"
          )
        ]),
        Location(),
        Location(),
        Location()
      )

      assert_errors expected, "BEGIN { 1 + }", [
        ["Expected a value after the operator.", 11..11]
      ]
    end

    def test_unterminated_embdoc
      assert_errors expression("1"), "1\n=begin\n", [
        ["Unterminated embdoc", 2..9]
      ]
    end

    def test_unterminated_i_list
      assert_errors expression("%i["), "%i[", [
        ["Expected a closing delimiter for a `%i` list.", 3..3]
      ]
    end

    def test_unterminated_w_list
      assert_errors expression("%w["), "%w[", [
        ["Expected a closing delimiter for a `%w` list.", 3..3]
      ]
    end

    def test_unterminated_W_list
      assert_errors expression("%W["), "%W[", [
        ["Expected a closing delimiter for a `%W` list.", 3..3]
      ]
    end

    def test_unterminated_regular_expression
      assert_errors expression("/hello"), "/hello", [
        ["Expected a closing delimiter for a regular expression.", 1..1]
      ]
    end

    def test_unterminated_regular_expression_with_heredoc
      source = "<<-END + /b\nEND\n"

      assert_errors expression(source), source, [
        ["Expected a closing delimiter for a regular expression.", 10..10]
      ]
    end

    def test_unterminated_xstring
      assert_errors expression("`hello"), "`hello", [
        ["Expected a closing delimiter for an xstring.", 1..1]
      ]
    end

    def test_unterminated_string
      assert_errors expression('"hello'), '"hello', [
        ["Expected a closing delimiter for an interpolated string.", 1..1]
      ]
    end

    def test_unterminated_s_symbol
      assert_errors expression("%s[abc"), "%s[abc", [
        ["Expected a closing delimiter for a dynamic symbol.", 3..3]
      ]
    end

    def test_unterminated_parenthesized_expression
      assert_errors expression('(1 + 2'), '(1 + 2', [
        ["Expected to be able to parse an expression.", 6..6],
        ["Expected a closing parenthesis.", 6..6]
      ]
    end

    def test_unterminated_argument_expression
      assert_errors expression('a %'), 'a %', [
        ["Unexpected end of input", 2..3],
        ["Expected a value after the operator.", 3..3],
      ]
    end

    def test_cr_without_lf_in_percent_expression
      assert_errors expression("%\r"), "%\r", [
        ["Invalid %% token", 0..2],
      ]
    end

    def test_1_2_3
      assert_errors expression("(1, 2, 3)"), "(1, 2, 3)", [
        ["Expected to be able to parse an expression.", 2..2],
        ["Expected a closing parenthesis.", 2..2],
        ["Expected a newline or semicolon after statement.", 2..2],
        ["Expected to be able to parse an expression.", 2..2],
        ["Expected a newline or semicolon after statement.", 5..5],
        ["Expected to be able to parse an expression.", 5..5],
        ["Expected a newline or semicolon after statement.", 8..8],
        ["Expected to be able to parse an expression.", 8..8],
      ]
    end

    def test_return_1_2_3
      assert_error_messages "return(1, 2, 3)", [
        "Expected to be able to parse an expression.",
        "Expected a closing parenthesis.",
        "Expected a newline or semicolon after statement.",
        "Expected to be able to parse an expression."
      ]
    end

    def test_return_1
      assert_errors expression("return 1,;"), "return 1,;", [
        ["Expected to be able to parse an argument.", 9..9]
      ]
    end

    def test_next_1_2_3
      assert_errors expression("next(1, 2, 3)"), "next(1, 2, 3)", [
        ["Expected to be able to parse an expression.", 6..6],
        ["Expected a closing parenthesis.", 6..6],
        ["Expected a newline or semicolon after statement.", 12..12],
        ["Expected to be able to parse an expression.", 12..12]
      ]
    end

    def test_next_1
      assert_errors expression("next 1,;"), "next 1,;", [
        ["Expected to be able to parse an argument.", 7..7]
      ]
    end

    def test_break_1_2_3
      assert_errors expression("break(1, 2, 3)"), "break(1, 2, 3)", [
        ["Expected to be able to parse an expression.", 7..7],
        ["Expected a closing parenthesis.", 7..7],
        ["Expected a newline or semicolon after statement.", 13..13],
        ["Expected to be able to parse an expression.", 13..13],
      ]
    end

    def test_break_1
      assert_errors expression("break 1,;"), "break 1,;", [
        ["Expected to be able to parse an argument.", 8..8]
      ]
    end

    def test_argument_forwarding_when_parent_is_not_forwarding
      assert_errors expression('def a(x, y, z); b(...); end'), 'def a(x, y, z); b(...); end', [
        ["unexpected ... when parent method is not forwarding.", 18..21]
      ]
    end

    def test_argument_forwarding_only_effects_its_own_internals
      assert_errors expression('def a(...); b(...); end; def c(x, y, z); b(...); end'),
        'def a(...); b(...); end; def c(x, y, z); b(...); end', [
          ["unexpected ... when parent method is not forwarding.", 43..46]
        ]
    end

    def test_top_level_constant_with_downcased_identifier
      assert_error_messages "::foo", [
        "Expected a constant after ::.",
        "Expected a newline or semicolon after statement."
      ]
    end

    def test_top_level_constant_starting_with_downcased_identifier
      assert_error_messages "::foo::A", [
        "Expected a constant after ::.",
        "Expected a newline or semicolon after statement."
      ]
    end

    def test_aliasing_global_variable_with_non_global_variable
      assert_errors expression("alias $a b"), "alias $a b", [
        ["Expected a global variable.", 9..10]
      ]
    end

    def test_aliasing_non_global_variable_with_global_variable
      assert_errors expression("alias a $b"), "alias a $b", [
        ["Expected a bare word or symbol argument.", 8..10]
      ]
    end

    def test_aliasing_global_variable_with_global_number_variable
      assert_errors expression("alias $a $1"), "alias $a $1", [
        ["Can't make alias for number variables.", 9..11]
      ]
    end

    def test_def_with_expression_receiver_and_no_identifier
      assert_errors expression("def (a); end"), "def (a); end", [
        ["Expected '.' or '::' after receiver", 7..7]
      ]
    end

    def test_def_with_multiple_statements_receiver
      assert_errors expression("def (\na\nb\n).c; end"), "def (\na\nb\n).c; end", [
        ["Expected closing ')' for receiver.", 7..7],
        ["Expected '.' or '::' after receiver", 7..7],
        ["Expected to be able to parse an expression.", 10..10],
        ["Expected to be able to parse an expression.", 11..11]
      ]
    end

    def test_def_with_empty_expression_receiver
      assert_errors expression("def ().a; end"), "def ().a; end", [
        ["Expected to be able to parse receiver.", 5..5]
      ]
    end

    def test_block_beginning_with_brace_and_ending_with_end
      assert_error_messages "x.each { x end", [
        "Expected a newline or semicolon after statement.",
        "Expected to be able to parse an expression.",
        "Expected to be able to parse an expression.",
        "Expected block beginning with '{' to end with '}'."
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
        "a"
      )

      assert_errors expected, "a(**kwargs, *args)", [
        ["Unexpected splat argument after double splat.", 12..17]
      ]
    end

    def test_arguments_after_block
      expected = CallNode(
        nil,
        nil,
        Location(),
        Location(),
        ArgumentsNode([
          BlockArgumentNode(expression("block"), Location()),
          expression("foo")
        ]),
        Location(),
        nil,
        0,
        "a"
      )

      assert_errors expected, "a(&block, foo)", [
        ["Unexpected argument after block argument.", 10..13]
      ]
    end

    def test_arguments_binding_power_for_and
      assert_error_messages "foo(*bar and baz)", [
        "Expected a ')' to close the argument list.",
        "Expected a newline or semicolon after statement.",
        "Expected to be able to parse an expression."
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
        "a"
      )

      assert_errors expected, "a(foo: bar, *args)", [
        ["Unexpected splat argument after double splat.", 12..17]
      ]
    end

    def test_module_definition_in_method_body
      expected = DefNode(
        Location(),
        nil,
        nil,
        StatementsNode([ModuleNode([], Location(), ConstantReadNode(), nil, Location(), "A")]),
        [],
        Location(),
        nil,
        nil,
        nil,
        nil,
        Location()
      )

      assert_errors expected, "def foo;module A;end;end", [
        ["Module definition in method body", 8..14]
      ]
    end

    def test_module_definition_in_method_body_within_block
      expected = DefNode(
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
              StatementsNode([ModuleNode([], Location(), ConstantReadNode(), nil, Location(), "Foo")]),
              Location(),
              Location()
            ),
            0,
            "bar"
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

      assert_errors expected, <<~RUBY, [["Module definition in method body", 21..27]]
        def foo
          bar do
            module Foo;end
          end
        end
      RUBY
    end

    def test_class_definition_in_method_body
      expected = DefNode(
        Location(),
        nil,
        nil,
        StatementsNode(
          [ClassNode(
            [],
            Location(),
            ConstantReadNode(),
            nil,
            nil,
            nil,
            Location(),
            "A"
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
        ["Class definition in method body", 8..13]
      ]
    end

    def test_bad_arguments
      expected = DefNode(
        Location(),
        nil,
        ParametersNode([
          RequiredParameterNode(:A),
          RequiredParameterNode(:@a),
          RequiredParameterNode(:$A),
          RequiredParameterNode(:@@a),
        ], [], [], nil, [], nil, nil),
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
        ["Formal argument cannot be a constant", 8..9],
        ["Formal argument cannot be an instance variable", 11..13],
        ["Formal argument cannot be a global variable", 15..17],
        ["Formal argument cannot be a class variable", 19..22],
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
        ["reserved for numbered parameter", 8..10],
        ["reserved for numbered parameter", 14..16],
        ["reserved for numbered parameter", 20..22],
        ["reserved for numbered parameter", 26..28],
        ["reserved for numbered parameter", 32..34],
        ["reserved for numbered parameter", 40..42],
        ["reserved for numbered parameter", 46..48],
        ["reserved for numbered parameter", 52..54],
        ["reserved for numbered parameter", 58..60],
      ]
    end

    def test_do_not_allow_trailing_commas_in_method_parameters
      expected = DefNode(
        Location(),
        nil,
        ParametersNode(
          [RequiredParameterNode(:a), RequiredParameterNode(:b), RequiredParameterNode(:c)],
          [],
          [],
          nil,
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
        ["Unexpected ','.", 13..14]
      ]
    end

    def test_do_not_allow_trailing_commas_in_lambda_parameters
      expected = LambdaNode(
        [:a, :b],
        Location(),
        Location(),
        Location(),
        BlockParametersNode(
          ParametersNode([RequiredParameterNode(:a), RequiredParameterNode(:b)], [], [], nil, [], nil, nil),
          [],
          Location(),
          Location()
        ),
        nil
      )
      assert_errors expected, "-> (a, b, ) {}", [
        ["Unexpected ','.", 8..9]
      ]
    end

    def test_do_not_allow_multiple_codepoints_in_a_single_character_literal
      expected = StringNode(Location(), Location(), nil, "\u0001\u0002")

      assert_errors expected, '?\u{0001 0002}', [
        ["Multiple codepoints at single character literal", 9..12]
      ]
    end

    def test_invalid_hex_escape
      assert_errors expression('"\\xx"'), '"\\xx"', [
        ["Invalid hex escape.", 1..3],
      ]
    end

    def test_do_not_allow_more_than_6_hexadecimal_digits_in_u_Unicode_character_notation
      expected = StringNode(Location(), Location(), Location(), "\u0001")

      assert_errors expected, '"\u{0000001}"', [
        ["invalid Unicode escape.", 4..11],
      ]
    end

    def test_do_not_allow_characters_other_than_0_9_a_f_and_A_F_in_u_Unicode_character_notation
      expected = StringNode(Location(), Location(), Location(), "\u0000z}")

      assert_errors expected, '"\u{000z}"', [
        ["unterminated Unicode escape", 7..7],
      ]
    end

    def test_unterminated_unicode_brackets_should_be_a_syntax_error
      assert_errors expression('?\\u{3'), '?\\u{3', [
        ["invalid Unicode escape.", 1..5],
      ]
    end

    def test_method_parameters_after_block
      expected = DefNode(
        Location(),
        nil,
        ParametersNode(
          [],
          [],
          [RequiredParameterNode(:a)],
          nil,
          [],
          nil,
          BlockParameterNode(Location(), Location())
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
        Location(),
        nil,
        ParametersNode([], [], [RequiredParameterNode(:a)], nil, [], nil, BlockParameterNode(nil, Location())),
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
        Location(),
        nil,
        ParametersNode(
          [],
          [],
          [RequiredParameterNode(:a)],
          nil,
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
        Location(),
        nil,
        ParametersNode(
          [],
          [],
          [RequiredParameterNode(:a)],
          nil,
          [KeywordParameterNode(Location(), nil)],
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
        Location(),
        nil,
        ParametersNode(
          [],
          [],
          [],
          nil,
          [KeywordParameterNode(Location(), nil)],
          KeywordRestParameterNode(Location(), Location()),
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
        Location(),
        nil,
        ParametersNode([], [], [], nil, [], ForwardingParameterNode(), nil),
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
        Location(),
        nil,
        ParametersNode(
          [],
          [],
          [RequiredParameterNode(:a)],
          nil,
          [KeywordParameterNode(Location(), nil)],
          KeywordRestParameterNode(Location(), Location()),
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
        Location(),
        nil,
        ParametersNode(
          [],
          [],
          [RequiredParameterNode(:a)],
          nil,
          [KeywordParameterNode(Location(), nil)],
          KeywordRestParameterNode(Location(), Location()),
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
        Location(),
        nil,
        ParametersNode(
          [],
          [],
          [RequiredParameterNode(:a)],
          nil,
          [KeywordParameterNode(Location(), nil)],
          KeywordRestParameterNode(Location(), Location()),
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
        Location(),
        nil,
        ParametersNode(
          [RequiredParameterNode(:a)],
          [
            OptionalParameterNode(:b, Location(), Location(), IntegerNode()),
            OptionalParameterNode(:d, Location(), Location(), IntegerNode())
          ],
          [RequiredParameterNode(:c), RequiredParameterNode(:e)],
          nil,
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
        ["Unexpected else without no when clauses in case statement.", 8..12]
      ]
    end

    def test_setter_method_cannot_be_defined_in_an_endless_method_definition
      expected = DefNode(
        Location(),
        nil,
        nil,
        StatementsNode([IntegerNode()]),
        [],
        Location(),
        nil,
        Location(),
        Location(),
        Location(),
        nil
      )

      assert_errors expected, "def a=() = 42", [
        ["Setter method cannot be defined in an endless method definition", 4..6]
      ]
    end

    def test_do_not_allow_forward_arguments_in_lambda_literals
      expected = LambdaNode(
        [:"..."],
        Location(),
        Location(),
        Location(),
        BlockParametersNode(ParametersNode([], [], [], nil, [], ForwardingParameterNode(), nil), [], Location(), Location()),
        nil
      )

      assert_errors expected, "->(...) {}", [
        ["Unexpected ...", 3..6]
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
          BlockParametersNode(ParametersNode([], [], [], nil, [], ForwardingParameterNode(), nil), [], Location(), Location()),
          nil,
          Location(),
          Location()
        ),
        0,
        "a"
      )

      assert_errors expected, "a {|...|}", [
        ["Unexpected ...", 4..7]
      ]
    end

    def test_dont_allow_return_inside_class_body
      expected = ClassNode(
        [],
        Location(),
        ConstantReadNode(),
        nil,
        nil,
        StatementsNode([ReturnNode(Location(), nil)]),
        Location(),
        "A"
      )

      assert_errors expected, "class A; return; end", [
        ["Invalid return in class/module body", 15..16]
      ]
    end

    def test_dont_allow_return_inside_module_body
      expected = ModuleNode(
        [],
        Location(),
        ConstantReadNode(),
        StatementsNode([ReturnNode(Location(), nil)]),
        Location(),
        "A"
      )

      assert_errors expected, "module A; return; end", [
        ["Invalid return in class/module body", 16..17]
      ]
    end

    def test_dont_allow_setting_to_back_and_nth_reference
      expected = BeginNode(
        Location(),
        StatementsNode([
          GlobalVariableWriteNode(Location(), NilNode(), Location()),
          GlobalVariableWriteNode(Location(), NilNode(), Location())
        ]),
        nil,
        nil,
        nil,
        Location()
      )

      assert_errors expected, "begin\n$+ = nil\n$1466 = nil\nend", [
        ["Can't set variable", 6..8],
        ["Can't set variable", 15..20]
      ]
    end

    def test_duplicated_parameter_names
      # For some reason, Ripper reports no error for Ruby 3.0 when you have
      # duplicated parameter names for positional parameters.
      unless RUBY_VERSION < "3.1.0"
        expected = DefNode(
          Location(),
          nil,
          ParametersNode([RequiredParameterNode(:a), RequiredParameterNode(:b), RequiredParameterNode(:a)], [], [], nil, [], nil, nil),
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
          ["Duplicated parameter name.", 12..13]
        ]
      end

      expected = DefNode(
        Location(),
        nil,
        ParametersNode([RequiredParameterNode(:a), RequiredParameterNode(:b)], [], [], RestParameterNode(Location(), Location()), [], nil, nil),
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
        ["Duplicated parameter name.", 13..14]
      ]

      expected = DefNode(
        Location(),
        nil,
        ParametersNode([RequiredParameterNode(:a), RequiredParameterNode(:b)], [], [], nil, [], KeywordRestParameterNode(Location(), Location()), nil),
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
        ["Duplicated parameter name.", 14..15]
      ]

      expected = DefNode(
        Location(),
        nil,
        ParametersNode([RequiredParameterNode(:a), RequiredParameterNode(:b)], [], [], nil, [], nil, BlockParameterNode(Location(), Location())),
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
        ["Duplicated parameter name.", 13..14]
      ]

      expected = DefNode(
        Location(),
        nil,
        ParametersNode([], [OptionalParameterNode(:a, Location(), Location(), IntegerNode())], [RequiredParameterNode(:b)], RestParameterNode(Location(), Location()), [], nil, nil),
        nil,
        [:a, :b, :c],
        Location(),
        nil,
        Location(),
        Location(),
        nil,
        Location()
      )

      assert_errors expected, "def foo(a = 1,b,*c);end", [["Unexpected parameter *", 16..17]]
    end

    def test_unterminated_global_variable
      assert_errors expression("$"), "$", [
        ["Invalid global variable.", 0..1]
      ]
    end

    private

    def assert_errors(expected, source, errors)
      # Ripper behaves differently on JRuby/TruffleRuby, so only check this on CRuby
      assert_nil Ripper.sexp_raw(source) if RUBY_ENGINE == "ruby"

      result = YARP.parse(source)
      node = result.value.statements.body.last

      assert_equal_nodes(expected, node, compare_location: false)
      assert_equal(errors, result.errors.map { |e| [e.message, e.location.start_offset..e.location.end_offset] })
    end

    def assert_error_messages(source, errors)
      assert_nil Ripper.sexp_raw(source)
      result = YARP.parse(source)
      assert_equal(errors, result.errors.map(&:message))
    end

    def expression(source)
      YARP.parse(source).value.statements.body.last
    end
  end
end
